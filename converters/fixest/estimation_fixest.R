# fixest `feols` fit -> `estimation` record (linear-fe/0.1).
#
# A worked converter: it reads a fitted fixest model and returns the record as a list,
# written to JSON with jsonlite. Written against fixest 0.14.2 and jsonlite 2.0.0.
#
#   library(fixest)
#   source("estimation_fixest.R")
#   fit <- feols(y ~ x1 + x2 | firm + year, data, cluster = ~firm)
#   rec <- estimation_record(fit)
#   estimation_write(rec, "fit.estimation.json")
#
# The record has no core digest (meta.core_digest is optional): computing it needs RFC 8785
# canonical JSON. Add it with the reference validator: `estimation digest --write FILE`.
#
# fixest keeps one set of dropped rows (`obs_selection$obsRemoved`: missing values and
# singletons together) and reports the singleton count only in a message. The converter
# recovers the input data from the fit's call environment, as fixest's own methods do, to
# tell the two apart; pass `data` if that environment is gone.

estimation_converter <- list(name = "estimation_fixest", version = "0.1.0")

.est_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

.est_uuid <- function() {
  h <- sprintf("%04x", sample.int(65536L, 8L) - 1L)
  h[4] <- sprintf("4%03x", strtoi(h[4], 16L) %% 4096L)                  # version 4
  h[5] <- sprintf("%04x", bitwOr(bitwAnd(strtoi(h[5], 16L), 0x3fffL), 0x8000L))  # variant
  paste0(h[1], h[2], "-", h[3], "-", h[4], "-", h[5], "-", h[6], h[7], h[8])
}

# Non-finite numbers as the format's strings; finite ones unchanged
.est_num <- function(x) {
  x <- unname(x)
  if (length(x) == 1L && is.numeric(x) && !is.finite(x)) {
    if (is.na(x) && !is.nan(x)) return(NULL)
    return(if (is.nan(x)) "NaN" else if (x > 0) "Infinity" else "-Infinity")
  }
  x
}

# fixest term name -> canonical {name, factors} (spec 4.4.1). fixest spells factor levels
# `var::level` (i(), and factor() in the linear part as `factor(var)level`)
.est_canonical <- function(term) {
  if (term == "(Intercept)") return(list(name = "(Intercept)", factors = list()))
  parts <- strsplit(term, "(?<!:):(?!:)", perl = TRUE)[[1]]
  factors <- lapply(parts, function(p) {
    m <- regmatches(p, regexec("^(.+)::(.+)$", p))[[1]]
    if (length(m) == 3L) return(list(variable = m[2], level = m[3]))
    m <- regmatches(p, regexec("^(?:as\\.)?factor\\(([^)]+)\\)(.+)$", p))[[1]]
    if (length(m) == 3L) return(list(variable = m[2], level = m[3]))
    list(variable = p)
  })
  has_level <- vapply(factors, function(f) !is.null(f$level), logical(1))
  if (any(has_level) && !all(has_level)) {
    name <- paste(vapply(factors, function(f)
      if (is.null(f$level)) paste0("c.", f$variable) else paste0(f$level, ".", f$variable), ""), collapse = "#")
  } else {
    name <- paste(vapply(factors, function(f) paste0(f$variable, if (is.null(f$level)) "" else f$level), ""),
                  collapse = ":")
  }
  list(name = name, factors = factors)
}

.est_vcov_type <- function(label) {
  if (grepl("^IID", label, ignore.case = TRUE)) return("iid")
  if (grepl("^Heteroskedasticity", label)) return("HC1")
  if (grepl("^Clustered", label)) return("CRV1")
  label
}

.est_cluster_vars <- function(fit, label) {
  flag <- fit$summary_flags$vcov
  if (inherits(flag, "formula")) return(all.vars(flag))
  if (!is.null(fit$call$cluster)) return(all.vars(as.formula(fit$call$cluster)))
  m <- regmatches(label, regexec("^Clustered \\((.+)\\)$", label))[[1]]  # the default: first FE
  if (length(m) == 2L) return(trimws(strsplit(m[2], "&", fixed = TRUE)[[1]]))
  character(0)
}

.est_software <- function() {
  pkgs <- setdiff(loadedNamespaces(), c(rownames(installed.packages(priority = "base")), "fixest"))
  comp <- function(p, role) {
    v <- as.character(utils::packageVersion(p))
    list(name = p, version = v, purl = sprintf("pkg:cran/%s@%s", p, v), role = role, source = "CRAN")
  }
  r <- paste(R.version$major, R.version$minor, sep = ".")
  c(list(comp("fixest", "estimator"),
         list(name = "R", version = r, purl = sprintf("pkg:generic/r@%s", r), role = "language")),
    lapply(sort(pkgs), comp, role = "dependency"))
}

estimation_record <- function(fit, data = NULL, call = TRUE, identifying = TRUE, publication = NULL) {
  stopifnot(inherits(fit, "fixest"))
  if (inherits(fit, "fixest_multi")) stop("a fixest_multi: convert each model, e.g. lapply(as.list(fit), estimation_record)")
  if (fit$method != "feols" || isTRUE(fit$iv)) stop("only OLS feols fits; IV and GLMs need other profiles")
  if (!is.null(fit$call$subset) || !is.null(fit$call$split) || !is.null(fit$call$fsplit))
    stop("subset/split fits aren't handled by this converter yet")
  if (is.null(data)) data <- eval(fit$call$data, fit$call_env)
  has_fe <- !is.null(fit$fixef_vars)

  # Sample: missing values vs singletons
  model_vars <- unique(c(all.vars(fit$fml_all$linear), if (has_fe) all.vars(fit$fml_all$fixef)))
  vc <- vcov(fit, attr = TRUE)
  label <- attr(vc, "vcov_type")
  clusters <- .est_cluster_vars(fit, label)
  wvar <- if (!is.null(fit$call$weights)) all.vars(as.formula(fit$call$weights)) else character(0)
  used_cols <- intersect(c(model_vars, clusters, wvar), names(data))
  rows_input <- fit$nobs_origin
  if (nrow(data) != rows_input) stop("`data` has ", nrow(data), " rows; the fit saw ", rows_input)
  n_missing <- sum(!stats::complete.cases(data[used_cols]))
  fixef_rm <- if (!is.null(fit$call$fixef.rm)) eval(fit$call$fixef.rm, fit$call_env) else "perfect_fit"
  drop_singletons <- has_fe && fixef_rm != "none"
  n_singletons <- if (drop_singletons) rows_input - fit$nobs - n_missing else 0L
  if (n_singletons < 0) stop("sample counts don't add up: pass the data the model was fitted on, unchanged")

  # Parameters
  ct <- coeftable(fit)
  ci <- confint(fit, level = 0.95)
  parameters <- lapply(rownames(ct), function(term) list(
    term = term, canonical = .est_canonical(term),
    estimate = .est_num(ct[term, 1]), std_error = .est_num(ct[term, 2]),
    statistic = .est_num(ct[term, 3]), p_value = .est_num(ct[term, 4]),
    conf_low = .est_num(ci[term, 1]), conf_high = .est_num(ci[term, 2])))
  collinear <- if (is.null(fit$collin.var)) character(0) else fit$collin.var
  parameters <- c(parameters, lapply(collinear, function(t)
    list(term = t, canonical = .est_canonical(t), dropped = "collinear")))

  # Default vcov
  used <- obs(fit)
  ssc <- attr(vc, "ssc")
  vcov_s <- list(kind = "matrix", labels = I(colnames(vc)),
                 data = lapply(seq_len(nrow(vc)), function(i) I(unname(vc[i, ]))),
                 type = .est_vcov_type(label), tool_type = label)
  if (length(clusters)) {
    n_cl <- lapply(clusters, function(v) length(unique(data[[v]][used])))
    names(n_cl) <- clusters
    vcov_s$cluster <- I(clusters)
    vcov_s$n_clusters <- n_cl
    vcov_s$n_clusters_min <- min(unlist(n_cl))
  }
  vcov_s$ssc <- list(convention = "fixest",
                     formula = "K.adj: (n-1)/(n-K) (n/(n-K)... per vcov type); G.adj: G/(G-1)",
                     factors = unclass(ssc)[c("K.adj", "K.fixef", "G.adj", "G.df", "t.df", "K.exact")],
                     K_counts = list(df.K = attr(vc, "df.K"), K.fixef = ssc$K.fixef))
  vcov_s$ssc$factors <- vcov_s$ssc$factors[!vapply(vcov_s$ssc$factors, is.null, logical(1))]
  vcov_s$df_t <- if (!is.null(attr(vc, "df.t"))) attr(vc, "df.t") else df.residual(fit)
  vcov_s$default <- TRUE

  # Metrics (tool's own values)
  metrics <- list(nobs = fit$nobs, n_singletons = n_singletons, df_residual = df.residual(fit),
                  r2 = .est_num(r2(fit, "r2")), adj_r2 = .est_num(r2(fit, "ar2")),
                  sigma = .est_num(sigma(fit)), rss = .est_num(fit$ssr), tss = .est_num(fit$ssr_null),
                  log_lik = .est_num(as.numeric(logLik(fit))), log_lik_null = .est_num(fit$ll_null),
                  sq_corr_fitted = .est_num(fit$sq.cor), conf_level = 0.95)
  if (has_fe) {
    metrics$r2_within <- .est_num(r2(fit, "wr2"))
    metrics$adj_r2_within <- .est_num(r2(fit, "war2"))
    metrics$log_lik_fe_only <- .est_num(fit$ll_fe_only)
  }
  metrics <- metrics[!vapply(metrics, is.null, logical(1))]

  options <- list(drop_singletons = drop_singletons, fixef_rm = fixef_rm,
                  collinearity_tolerance = if (!is.null(fit$call$collin.tol)) eval(fit$call$collin.tol, fit$call_env) else 1e-10)
  if (has_fe) {
    options$tolerance <- fit$fixef.tol
    options$max_iterations <- fit$fixef.iter
  }
  spec <- list(formula = list(text = paste(deparse(fit$fml_all$linear, width.cutoff = 500L), collapse = ""),
                              syntax = "fixest"),
               terms = I(names(coef(fit))),
               weights = if (length(wvar)) list(variable = wvar, type = "analytic") else NULL,
               fixed_effects = I(if (has_fe) fit$fixef_vars else character(0)),
               clusters = I(clusters),
               sample = list(restriction = NULL, rows_input = rows_input,
                             dropped = list(missing = n_missing, singletons = n_singletons)),
               options = options)
  if (has_fe) spec$formula$text <- paste(spec$formula$text, "|", paste(fit$fixef_vars, collapse = " + "))
  if (isTRUE(call)) spec$call <- paste(deparse(fit$call, width.cutoff = 500L), collapse = " ")

  structures <- list(vcov = list(vcov_s))
  if (has_fe) {
    structures$fixed_effects <- lapply(names(fit$fixef_sizes), function(n)
      list(kind = "object", name = n, levels = unname(fit$fixef_sizes[[n]])))
    it <- fit$iterations
    structures$numerics <- list(kind = "object", iterative = TRUE, algorithm = "map",
                                tolerance = fit$fixef.tol, max_iterations = fit$fixef.iter,
                                iterations = if (length(it)) max(it) else NULL,
                                iterations_by_variable = if (length(it)) I(it) else NULL,
                                collinearity_tolerance = spec$options$collinearity_tolerance,
                                collinear_terms = I(collinear),
                                collinearity_min_norm = .est_num(fit$collin.min_norm))
    structures$numerics <- structures$numerics[!vapply(structures$numerics, is.null, logical(1))]
  }

  si <- Sys.info()
  provenance <- list(software = .est_software(),
                     environment = list(os = unname(si[["sysname"]]), kernel = unname(si[["release"]]),
                                        machine = unname(si[["machine"]]),
                                        lapack = La_version(),
                                        threads = list(fixest = getFixest_nthreads())),
                     data = list(list(role = "estimation", rows = rows_input, columns = I(names(data)))))
  if (identifying) {
    provenance$agent <- list(user = unname(si[["user"]]), host = unname(si[["nodename"]]))
    provenance$execution <- list(invocation = list(argv = I(commandArgs())))
  }

  meta <- list(id = .est_uuid(), created = .est_now(), status = "ok",
               estimator = list(family = "linear", method = "ols"),
               responses = I(all.vars(fit$fml_all$linear)[1]),
               profiles = I(if (has_fe) c("inference/0.1", "linear-fe/0.1") else "inference/0.1"))
  if (n_singletons > 0)
    meta$messages <- list(list(level = "info", code = "singletons", source = "fixest",
                               message = sprintf("%d singleton rows dropped", n_singletons)))

  rec <- list(schema = "estimation/0.1", meta = meta, specification = spec, metrics = metrics,
              parameters = parameters, structures = structures, provenance = provenance)
  if (!is.null(publication)) rec$publication <- publication
  rec$history <- list(list(when = meta$created, by = estimation_converter, action = "created",
                           sections = I(setdiff(names(rec), "schema"))))
  rec
}

# Write a record as JSON. 17 significant digits so doubles round-trip exactly; NULL as null
estimation_write <- function(rec, file) {
  jsonlite::write_json(rec, file, auto_unbox = TRUE, digits = I(17), null = "null", na = "null", pretty = 1)
  invisible(rec)
}

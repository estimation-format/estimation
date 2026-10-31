# Generics, writing, and helpers shared by the writers for each model class.

estrec_info <- function() {
  list(name = "estrec", version = as.character(utils::packageVersion("estrec")))
}

# Convert a fitted model to an estimation record (a list); methods per model class
to_estimation <- function(fit, ...) UseMethod("to_estimation")

to_estimation.default <- function(fit, ...) {
  stop("estrec has no writer for class ", paste(class(fit), collapse = "/"),
       "; it writes fixest feols fits for now", call. = FALSE)
}

is_estimation_record <- function(x) {
  is.list(x) && identical(x$schema, "estimation/0.1")
}

# Write one record per file. `x` is a fitted model, a record, or a list of records. With more
# than one record, `path` is numbered: fit.estimation.json -> fit-1.estimation.json, ...
write_estimation <- function(x, path, ...) {
  recs <- if (is_estimation_record(x)) list(x)
          else if (is.list(x) && length(x) && all(vapply(x, is_estimation_record, logical(1)))) x
          else to_estimation(x, ...)
  if (is_estimation_record(recs)) recs <- list(recs)
  paths <- if (length(recs) == 1L) path else .est_numbered(path, length(recs))
  for (i in seq_along(recs)) {
    # 17 significant digits, so doubles round-trip exactly
    jsonlite::write_json(recs[[i]], paths[i], auto_unbox = TRUE, digits = I(17),
                         null = "null", na = "null", pretty = TRUE)
  }
  invisible(paths)
}

.est_numbered <- function(path, n) {
  ext <- regmatches(path, regexpr("(\\.estimation)?\\.json$", path))
  if (!length(ext)) ext <- ""
  stem <- substr(path, 1L, nchar(path) - nchar(ext))
  sprintf("%s-%d%s", stem, seq_len(n), if (nzchar(ext)) ext else ".json")
}

.est_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# A version 4 UUID. Uses a fresh RNG stream and restores the caller's, so writing a record
# neither changes the user's random numbers nor repeats ids after set.seed()
.est_uuid <- function() {
  env <- globalenv()
  if (exists(".Random.seed", envir = env, inherits = FALSE)) {
    old <- get(".Random.seed", envir = env, inherits = FALSE)
    on.exit(assign(".Random.seed", old, envir = env))
  } else {
    on.exit(rm(".Random.seed", envir = env))
  }
  set.seed(NULL)
  h <- sprintf("%04x", sample.int(65536L, 8L) - 1L)
  h[4] <- sprintf("4%03x", strtoi(h[4], 16L) %% 4096L)
  h[5] <- sprintf("%04x", bitwOr(bitwAnd(strtoi(h[5], 16L), 0x3fffL), 0x8000L))
  paste0(h[1], h[2], "-", h[3], "-", h[4], "-", h[5], "-", h[6], h[7], h[8])
}

# Non-finite numbers as the format's strings (spec section 2); NA as NULL
.est_num <- function(x) {
  x <- unname(x)
  if (length(x) == 1L && is.numeric(x) && !is.finite(x)) {
    if (is.na(x) && !is.nan(x)) return(NULL)
    return(if (is.nan(x)) "NaN" else if (x > 0) "Infinity" else "-Infinity")
  }
  x
}

.est_compact <- function(x) x[!vapply(x, is.null, logical(1))]

# Term name -> canonical {name, factors} (spec 4.4.1). fixest and R spell factor levels
# `var::level` (i()) or `factor(var)level`
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
      if (is.null(f$level)) paste0("c.", f$variable) else paste0(f$level, ".", f$variable), ""),
      collapse = "#")
  } else {
    name <- paste(vapply(factors, function(f)
      paste0(f$variable, if (is.null(f$level)) "" else f$level), ""), collapse = ":")
  }
  list(name = name, factors = factors)
}

# provenance.software: the estimator first, then R, then the other loaded packages
.est_software <- function(estimator) {
  base <- rownames(utils::installed.packages(priority = "base"))
  pkgs <- setdiff(loadedNamespaces(), c(base, estimator, "estrec"))
  comp <- function(p, role) {
    v <- as.character(utils::packageVersion(p))
    list(name = p, version = v, purl = sprintf("pkg:cran/%s@%s", p, v), role = role,
         source = "CRAN")
  }
  r <- paste(R.version$major, R.version$minor, sep = ".")
  c(list(comp(estimator, "estimator"),
         list(name = "R", version = r, purl = sprintf("pkg:generic/r@%s", r), role = "language"),
         comp("estrec", "writer")),
    lapply(sort(pkgs), comp, role = "dependency"))
}

.est_environment <- function(threads = NULL) {
  si <- Sys.info()
  .est_compact(list(os = unname(si[["sysname"]]), kernel = unname(si[["release"]]),
                    machine = unname(si[["machine"]]), lapack = La_version(),
                    blas = if (nzchar(extSoftVersion()[["BLAS"]])) extSoftVersion()[["BLAS"]],
                    threads = threads))
}

# Identifying details (spec 4.7): kept unless identifying = FALSE
.est_agent <- function() {
  si <- Sys.info()
  list(user = unname(si[["user"]]), host = unname(si[["nodename"]]))
}

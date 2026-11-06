# Table specs (estrec-table/0.1, spec/table.md): render a spec with modelsummary.

# Render a table spec: a path to an *.estrec-table.json file or the spec as a list. The
# records come from the spec's sources (relative to its folder, or `base_dir`) and from
# `records` (records, a list of them, or read_collection()'s result). Each column becomes a
# modelsummary model from the record's tidy() (with the column's vcov), so the output formats
# and themes are modelsummary's; `...` goes to modelsummary().
render_table <- function(spec, output = "default", records = NULL, base_dir = NULL, ...) {
  if (!requireNamespace("modelsummary", quietly = TRUE))
    stop("render_table() needs the 'modelsummary' package", call. = FALSE)
  if (is.character(spec)) {
    if (is.null(base_dir)) base_dir <- dirname(spec)
    spec <- jsonlite::fromJSON(spec, simplifyVector = FALSE)
  }
  if (!identical(spec$schema, "estrec-table/0.1"))
    stop("not an estrec-table/0.1 spec", call. = FALSE)
  idx <- .tab_index(spec, records, base_dir)
  cols <- spec$columns
  if (!length(cols)) stop("the spec has no columns", call. = FALSE)
  src_ids <- vapply(spec$sources %||% list(), function(s) as.character(s$id), "")
  found <- lapply(seq_along(cols), function(i) {
    c <- cols[[i]]
    if (!is.null(c$source) && !c$source %in% src_ids)
      stop("columns[", i - 1, "].source: no source '", c$source, "'", call. = FALSE)
    f <- (if (!is.null(c$source)) idx[[paste0(c$source, "\r", c$record)]]) %||% idx[[c$record]]
    if (is.null(f)) stop("columns[", i - 1, "]: record ", c$record, " not found", call. = FALSE)
    f
  })
  fmt <- spec$format %||% list()
  digits <- fmt$digits %||% 3
  big <- fmt$thousands %||% ","
  missing <- fmt$missing %||% ""
  unc <- if ("uncertainty" %in% names(spec)) spec$uncertainty else "std_error"
  lines <- .tab_lines(unc)
  p_digits <- fmt$p_digits %||% digits
  p_style <- fmt$p_style %||% "fixed"

  # each line under the estimates is filled here, by the spec's rules, into a text column
  # (line1, line2, ...) that modelsummary's `statistic` templates name
  tidies <- lapply(seq_along(cols), function(i) {
    c <- cols[[i]]
    vc <- c$vcov
    if (is.numeric(vc)) vc <- vc + 1   # the spec counts from 0, tidy() from 1
    t <- tidy.estimation_record(found[[i]], vcov = vc, component = c$component)
    if (!is.null(c$response) && "response" %in% names(t)) t <- t[t$response %in% c$response, , drop = FALSE]
    for (k in seq_along(lines))
      t[[paste0("line", k)]] <- vapply(seq_len(nrow(t)), function(j)
        .tab_fill(lines[[k]], t[j, , drop = FALSE], digits, p_digits, p_style, missing), "")
    t
  })
  headers <- vapply(seq_along(cols), function(i) {
    h <- cols[[i]]$header %||% attr(found[[i]], "member")$label %||% found[[i]]$meta$title
    if (is.null(h)) sprintf("(%d)", i) else as.character(h)
  }, "")
  headers <- make.unique(headers, sep = " ")

  # terms: listed rows first, then unlisted ones (by first appearance) through keep/drop
  coef_map <- character()
  taken <- character()
  for (r in spec$rows %||% list()) {
    names_ <- unlist(r$terms %||% r$term)
    lab <- r$label %||% names_[1]
    coef_map <- c(coef_map, stats::setNames(rep(lab, length(names_)), names_))
    taken <- c(taken, names_)
  }
  if (!isFALSE(spec$keep_unlisted)) {
    keep <- unlist(spec$keep); drop <- unlist(spec$drop)
    for (p in c(keep, drop)) tryCatch(grepl(p, "", perl = TRUE),
                                      error = function(e) stop("pattern doesn't compile: ", p, call. = FALSE))
    seen <- character()
    for (t in tidies) for (term in t$term) {
      if (term %in% c(taken, seen)) next
      if (length(keep) && !any(vapply(keep, grepl, TRUE, term, perl = TRUE))) next
      if (length(drop) && any(vapply(drop, grepl, TRUE, term, perl = TRUE))) next
      seen <- c(seen, term)
    }
    coef_map <- c(coef_map, stats::setNames(seen, seen))
  }

  models <- lapply(tidies, function(t) structure(list(tidy = t, glance = data.frame(nobs = NA)),
                                                 class = "modelsummary_list"))
  names(models) <- headers

  stat_rows <- lapply(spec$stats %||% list(), function(s) {
    d <- s$digits %||% digits
    if (!is.null(s$values)) {
      if (length(s$values) != length(cols))
        stop("a text row has ", length(s$values), " values for ", length(cols), " columns", call. = FALSE)
      return(c(s$label, vapply(s$values, as.character, "")))
    }
    cells <- vapply(seq_along(cols), function(i) {
      rec <- found[[i]]; vc <- cols[[i]]$vcov
      if (is.numeric(vc)) vc <- vc + 1
      if (!is.null(s$metric)) {
        v <- rec$metrics[[s$metric]]
        v <- if (is.null(v)) NULL else .est_metric_value(v)
        if (is.null(v) && s$metric == "rmse" && !is.null(rec$metrics$rss) && !is.null(rec$metrics$nobs))
          v <- sqrt(.est_dbl(rec$metrics$rss) / .est_dbl(rec$metrics$nobs))
        return(.tab_value(v, d, big, missing))
      }
      if (!is.null(s$vcov)) {
        v <- .est_pick_vcov(rec, vc)
        if (is.null(v)) return(missing)
        if (s$vcov == "type") return(.est_vcov_label(v))
        n <- unlist(v$n_clusters)
        return(if (length(n)) paste(vapply(n, .tab_value, "", 0, big, missing), collapse = " / ") else missing)
      }
      if (!is.null(s$fixed_effect))
        return(if (s$fixed_effect %in% unlist(rec$specification$fixed_effects)) fmt$fe_yes %||% "Yes"
               else fmt$fe_no %||% "")
      if (!is.null(s$test)) {
        tt <- Filter(function(t) identical(t$label, s$test), rec$tests %||% list())
        if (!length(tt)) tt <- Filter(function(t) identical(t$name, s$test), rec$tests %||% list())
        if (!length(tt)) return(missing)
        which <- s$value %||% "statistic"
        v <- .est_dbl(tt[[1]][[which]])
        if (is.na(v)) return(missing)
        return(if (which == "p_value") .tab_p(v, s$digits %||% p_digits, p_style) else .tab_fixed(v, d))
      }
      missing
    }, "")
    label <- s$label %||% (if (!is.null(s$metric)) .tab_stat_labels[s$metric] %|NA|% s$metric
                           else if (!is.null(s$vcov)) (if (s$vcov == "type") "Std. errors" else "Clusters")
                           else if (!is.null(s$fixed_effect)) paste0("FE: ", s$fixed_effect)
                           else s$test)
    c(unname(label), cells)
  })
  add_rows <- NULL
  if (length(stat_rows)) {
    add_rows <- as.data.frame(do.call(rbind, stat_rows), stringsAsFactors = FALSE)
    names(add_rows) <- c("term", headers)
  }

  stars <- unlist(spec$stars)
  star_arg <- FALSE
  if (length(stars)) {
    sym <- unlist(fmt$star_symbols) %||% strrep("*", seq_along(stars))
    star_arg <- stats::setNames(stars, sym)
  }
  statistic <- if (length(lines)) sprintf("{line%d}", seq_along(lines)) else NULL
  notes <- c(unlist(spec$notes), .tab_unc_note(unc, lines))
  args <- list(models, output = output, coef_map = coef_map, statistic = statistic,
               stars = star_arg, fmt = digits, gof_omit = ".*", add_rows = add_rows)
  if (!is.null(spec$title)) args$title <- spec$title
  if (length(notes)) args$notes <- as.list(notes)
  do.call(modelsummary::modelsummary, c(args, list(...)))
}

.tab_stat_labels <- c(nobs = "N", r2 = "R\u00b2", adj_r2 = "Adj. R\u00b2", r2_within = "Within R\u00b2",
                      adj_r2_within = "Adj. within R\u00b2", pseudo_r2 = "Pseudo R\u00b2", aic = "AIC",
                      bic = "BIC", log_lik = "Log lik.", rmse = "RMSE", f_stat = "F")

`%|NA|%` <- function(a, b) if (length(a) != 1L || is.na(a)) b else a

# lines under each estimate (spec/table.md section 5)
.tab_named_lines <- c(std_error = "({std_error})", statistic = "({statistic})", p_value = "[{p_value}]",
                      conf_int = "[{conf_low}, {conf_high}]")
.tab_placeholders <- c(estimate = "estimate", std_error = "std.error", statistic = "statistic",
                       p_value = "p.value", conf_low = "conf.low", conf_high = "conf.high")

.tab_lines <- function(unc) {
  if (is.null(unc)) return(character())
  items <- unlist(unc)
  vapply(seq_along(items), function(j) {
    x <- items[[j]]
    if (x %in% names(.tab_named_lines)) return(unname(.tab_named_lines[x]))
    if (!grepl("{", x, fixed = TRUE))
      stop("uncertainty[", j - 1, "]: '", x, "' is neither a name (",
           paste(names(.tab_named_lines), collapse = ", "), ") nor a template", call. = FALSE)
    ph <- regmatches(x, gregexpr("\\{([^{}]*)\\}", x))[[1]]
    ph <- substr(ph, 2, nchar(ph) - 1)
    bad <- setdiff(ph, names(.tab_placeholders))
    if (length(bad)) stop("uncertainty[", j - 1, "]: unknown placeholder {", bad[1], "}; use ",
                          paste(names(.tab_placeholders), collapse = ", "), call. = FALSE)
    if (!length(ph)) stop("uncertainty[", j - 1, "]: a template needs at least one placeholder", call. = FALSE)
    x
  }, "")
}

.tab_fixed <- function(x, digits) {
  if (is.na(x)) return("")
  if (!is.finite(x)) return(if (x > 0) "Inf" else "-Inf")
  s <- formatC(x, digits = digits, format = "f")
  if (startsWith(s, "-") && as.numeric(s) == 0) s <- substring(s, 2)
  s
}

.tab_p <- function(p, digits, style) {
  if (is.na(p)) return("")
  if (identical(style, "less_than") && p < 10^-digits) return(paste0("<", .tab_fixed(10^-digits, digits)))
  .tab_fixed(p, digits)
}

.tab_fill <- function(template, row, digits, p_digits, p_style, missing) {
  ph <- regmatches(template, gregexpr("\\{([^{}]*)\\}", template))[[1]]
  out <- template
  for (m in unique(ph)) {
    name <- substr(m, 2, nchar(m) - 1)
    x <- row[[.tab_placeholders[[name]]]]
    if (is.null(x) || is.na(x)) return(missing)
    val <- if (name == "p_value") .tab_p(x, p_digits, p_style) else .tab_fixed(x, digits)
    out <- gsub(m, val, out, fixed = TRUE)
  }
  out
}

.tab_unc_note <- function(unc, lines) {
  if (is.null(unc) || !length(lines)) return(NULL)
  named <- c(std_error = "Standard errors in parentheses.", statistic = "Test statistics in parentheses.",
             p_value = "p-values in brackets.", conf_int = "Confidence intervals in brackets.")
  if (is.character(unc) && length(unc) == 1L && unc %in% names(named)) return(unname(named[unc]))
  words <- c(estimate = "estimate", std_error = "standard error", statistic = "test statistic",
             p_value = "p-value", conf_low = "lower bound", conf_high = "upper bound")
  parts <- vapply(lines, function(t) {
    t <- sub("{conf_low}, {conf_high}", "confidence interval", t, fixed = TRUE)
    for (w in names(words)) t <- gsub(paste0("{", w, "}"), words[[w]], t, fixed = TRUE)
    t
  }, "")
  paste0("Under each estimate: ", paste(parts, collapse = "; "), ".")
}

.tab_value <- function(v, digits, big, missing) {
  if (is.null(v) || length(v) != 1L || (is.atomic(v) && is.na(v) && !is.nan(v))) return(missing)
  if (is.logical(v)) return(if (v) "Yes" else "No")
  if (is.character(v)) return(v)
  if (is.nan(v)) return(missing)
  if (is.finite(v) && v == round(v) && abs(v) < 1e15)
    return(formatC(v, format = "d", big.mark = big))
  if (!is.finite(v)) return(if (v > 0) "Inf" else "-Inf")
  .tab_fixed(v, digits)
}

# Records a spec can use, keyed by meta.id and by "<source>\r<meta.id>"
.tab_index <- function(spec, records, base_dir) {
  idx <- list()
  add <- function(rec, src) {
    id <- rec$meta$id
    if (is.null(id)) return()
    if (!inherits(rec, "estimation_record")) rec <- .est_as_record(rec)
    if (!is.null(src) && is.null(idx[[paste0(src, "\r", id)]])) idx[[paste0(src, "\r", id)]] <<- rec
    if (is.null(idx[[id]])) idx[[id]] <<- rec
  }
  if (!is.null(records)) {
    recs <- if (is_estimation_record(records)) list(records) else records
    for (r in recs) add(r, NULL)
  }
  if (!is.null(base_dir)) {
    for (s in spec$sources %||% list()) {
      p <- file.path(base_dir, s$path)
      recs <- if (dir.exists(p)) read_estimation(p)
              else {
                doc <- jsonlite::fromJSON(p, simplifyVector = FALSE)
                if (identical(doc$schema, "estrec-collection/0.1")) read_collection(p)
                else list(read_estimation(p))
              }
      for (r in recs) add(r, s$id)
    }
  }
  idx
}

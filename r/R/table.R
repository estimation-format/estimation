# Table specs (estimation-table/0.1, spec/table.md): render a spec with modelsummary.

# Render a table spec: a path to an *.estimation-table.json file or the spec as a list. The
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
  if (!identical(spec$schema, "estimation-table/0.1"))
    stop("not an estimation-table/0.1 spec", call. = FALSE)
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

  tidies <- lapply(seq_along(cols), function(i) {
    c <- cols[[i]]
    vc <- c$vcov
    if (is.numeric(vc)) vc <- vc + 1   # the spec counts from 0, tidy() from 1
    t <- tidy.estimation_record(found[[i]], vcov = vc, component = c$component)
    if (!is.null(c$response) && "response" %in% names(t)) t <- t[t$response %in% c$response, , drop = FALSE]
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
        v <- .est_dbl(tt[[1]][[s$value %||% "statistic"]])
        return(if (is.na(v)) missing else formatC(v, digits = d, format = "f"))
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
  statistic <- switch(unc %||% "none", std_error = "({std.error})", statistic = "({statistic})",
                      p_value = "[{p.value}]", conf_int = "[{conf.low}, {conf.high}]", none = NULL)
  notes <- c(unlist(spec$notes),
             switch(unc %||% "none", std_error = "Standard errors in parentheses.",
                    statistic = "Test statistics in parentheses.", p_value = "p-values in brackets.",
                    conf_int = "Confidence intervals in brackets.", none = NULL))
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

.tab_value <- function(v, digits, big, missing) {
  if (is.null(v) || length(v) != 1L || (is.atomic(v) && is.na(v) && !is.nan(v))) return(missing)
  if (is.logical(v)) return(if (v) "Yes" else "No")
  if (is.character(v)) return(v)
  if (is.nan(v)) return(missing)
  if (is.finite(v) && v == round(v) && abs(v) < 1e15)
    return(formatC(v, format = "d", big.mark = big))
  if (!is.finite(v)) return(if (v > 0) "Inf" else "-Inf")
  formatC(v, digits = digits, format = "f")
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
                if (identical(doc$schema, "estimation-collection/0.1")) read_collection(p)
                else list(read_estimation(p))
              }
      for (r in recs) add(r, s$id)
    }
  }
  idx
}

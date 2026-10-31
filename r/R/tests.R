# Hypothesis tests in a record's `tests` (spec 4.8): add_test() appends one, computed from the
# record's own parameters and vcov, or converted from a fixest wald() result.

# Append a test to a record. `test` is
#   - a hypothesis as text: "x = x2", "x + x2 = 1", "x = 0, x2 = 0" (a Wald test of the
#     restrictions), or an expression without "=", "x + x2" (a linear combination: estimate,
#     standard error, interval and t test against 0). Terms are parameters[*].term; quote names
#     that aren't syntactic with backticks: "`(Intercept)` = 0";
#   - a fixest wald() result (a list with stat, p, df1, df2, vcov);
#   - a test object (a list with name and statistic or p_value), added as is.
# `vcov` picks the structures.vcov entry, by type ("HC1") or list(type =, cluster =); NULL is
# the default one.
add_test <- function(record, test, vcov = NULL, label = NULL, category = NULL, id = NULL,
                     tags = NULL, origin = "postestimation", by = estrec_info()) {
  if (!is_estimation_record(record)) stop("`record` must be an estimation record", call. = FALSE)
  t <- if (is.character(test) && length(test) == 1L) .est_linear_test(record, test, vcov)
       else if (is.list(test) && !is.null(test$stat)) .est_from_wald(test, record)
       else if (is.list(test) && !is.null(test$name)) test
       else stop("`test` must be a hypothesis string, a fixest wald() result or a test object",
                 call. = FALSE)
  if (!is.null(category)) t$category <- category
  if (!is.null(label)) t$label <- label
  if (length(tags)) t$tags <- I(tags)
  t$origin <- t$origin %||% origin
  taken <- vapply(record$tests %||% list(), function(x) x$id %||% "", "")
  if (is.null(id)) {
    n <- length(taken) + 1L
    while (paste0("t", n) %in% taken) n <- n + 1L
    id <- paste0("t", n)
  } else if (id %in% taken) {
    stop("a test with id ", id, " is already in the record", call. = FALSE)
  }
  added <- .est_now()
  t <- c(list(id = id), t[setdiff(names(t), "id")], list(added = added))
  record$tests <- c(record$tests, list(t))
  record$history <- c(record$history, list(list(when = added, by = by, action = "extended",
                                                sections = I("tests"))))
  record
}

.est_pick_vcov <- function(record, vcov) {
  vs <- record$structures$vcov
  if (!length(vs)) stop("the record has no structures.vcov", call. = FALSE)
  if (is.null(vcov)) {
    d <- Filter(function(v) isTRUE(v$default), vs)
    v <- if (length(d)) d[[1]] else vs[[1]]
  } else {
    want <- if (is.list(vcov)) vcov else list(type = vcov)
    m <- Filter(function(v) identical(v$type, want$type) &&
                  (is.null(want$cluster) || identical(as.character(v$cluster), as.character(want$cluster))), vs)
    if (!length(m)) stop("no structures.vcov entry with type ", want$type, call. = FALSE)
    v <- m[[1]]
  }
  if (!identical(v$kind, "matrix")) stop("the vcov is spilled to an attachment; load it first", call. = FALSE)
  labels <- as.character(unlist(v$labels))
  V <- do.call(rbind, lapply(v$data, function(r) as.numeric(unlist(r))))
  dimnames(V) <- list(labels, labels)
  list(entry = v, V = V)
}

# Restrictions R b = q from text, by evaluating each side as a linear function of the terms
.est_restrictions <- function(text, labels) {
  parts <- trimws(strsplit(text, ",", fixed = TRUE)[[1]])
  is_eq <- grepl("=", parts, fixed = TRUE)
  if (any(is_eq) && !all(is_eq)) stop("give every restriction an `=`, or none (a linear combination)", call. = FALSE)
  rows <- lapply(parts, function(p) {
    sides <- if (grepl("=", p, fixed = TRUE)) strsplit(p, "=", fixed = TRUE)[[1]] else c(p, "0")
    if (length(sides) != 2L) stop("can't read the restriction ", p, call. = FALSE)
    e <- tryCatch(str2lang(sprintf("(%s) - (%s)", sides[1], sides[2])),
                  error = function(err) stop("can't read ", p, ": ", conditionMessage(err), call. = FALSE))
    used <- all.vars(e)
    unknown <- setdiff(used, labels)
    if (length(unknown)) stop("not a term in parameters: ", paste(unknown, collapse = ", "), call. = FALSE)
    f <- function(b) {
      env <- list2env(as.list(stats::setNames(b, labels)), parent = baseenv())
      as.numeric(eval(e, env))
    }
    k <- length(labels)
    c0 <- f(rep(0, k))
    a <- vapply(seq_len(k), function(i) f(replace(rep(0, k), i, 1)) - c0, 0)
    z <- sqrt(seq_len(k) + 0.5)  # fixed points: no RNG use
    if (abs(f(z) - (c0 + sum(a * z))) > 1e-8 * (1 + abs(f(z)))) stop(p, " isn't linear in the terms", call. = FALSE)
    list(a = a, q = -c0, used = used)
  })
  list(R = do.call(rbind, lapply(rows, `[[`, "a")), q = vapply(rows, `[[`, 0, "q"),
       terms = unique(unlist(lapply(rows, `[[`, "used"))), equality = all(is_eq))
}

.est_linear_test <- function(record, text, vcov) {
  pv <- .est_pick_vcov(record, vcov)
  labels <- rownames(pv$V)
  est <- vapply(record$parameters, function(p) if (is.numeric(p$estimate)) p$estimate else NA_real_, 0)
  names(est) <- vapply(record$parameters, `[[`, "", "term")
  b <- est[labels]
  if (anyNA(b)) stop("parameters and the vcov labels don't match", call. = FALSE)
  rs <- .est_restrictions(text, labels)
  R <- rs$R; q <- rs$q; J <- nrow(R)
  # keep only the columns the test uses, so the record stays small
  keep <- colSums(abs(R)) > 0
  restr <- list(R = lapply(seq_len(J), function(i) I(unname(R[i, keep]))), q = I(unname(q)),
                labels = I(labels[keep]))
  df <- pv$entry$df_t
  vtag <- .est_compact(list(type = pv$entry$type, cluster = if (length(pv$entry$cluster)) I(as.character(unlist(pv$entry$cluster)))))
  hyp <- list(text = text, terms = I(rs$terms), restrictions = restr)
  d <- R %*% b - q
  RVR <- R %*% pv$V %*% t(R)
  if (!rs$equality) {
    # a linear combination: estimate of R b, its SE and interval, t test against 0
    if (J != 1L) stop("a linear combination is one expression; for joint tests use `=`", call. = FALSE)
    se <- sqrt(RVR[1, 1])
    lev <- record$metrics$conf_level %||% 0.95
    use_t <- is.numeric(df) && is.finite(df)
    crit <- if (use_t) stats::qt(1 - (1 - lev) / 2, df) else stats::qnorm(1 - (1 - lev) / 2)
    stat <- d[1] / se
    return(.est_compact(list(
      category = "linear_combination", name = if (use_t) "t" else "z", hypothesis = hyp,
      estimate = .est_num(d[1]), std_error = .est_num(se), conf_low = .est_num(d[1] - crit * se),
      conf_high = .est_num(d[1] + crit * se), statistic = .est_num(stat),
      distribution = if (use_t) "t" else "normal", df = if (use_t) df,
      p_value = .est_num(2 * (if (use_t) stats::pt(-abs(stat), df) else stats::pnorm(-abs(stat)))),
      method = "wald", vcov = vtag, source = .est_source(text))))
  }
  W <- as.numeric(t(d) %*% solve(RVR, d))
  use_f <- is.numeric(df) && is.finite(df)
  .est_compact(list(
    category = "restriction", name = "wald", hypothesis = hyp,
    statistic = .est_num(if (use_f) W / J else W), distribution = if (use_f) "F" else "chi2",
    df1 = if (use_f) J, df2 = if (use_f) df, df = if (!use_f) J,
    p_value = .est_num(if (use_f) stats::pf(W / J, J, df, lower.tail = FALSE) else stats::pchisq(W, J, lower.tail = FALSE)),
    method = "wald", vcov = vtag, source = .est_source(text)))
}

.est_source <- function(text) {
  c(estrec_info(), list(call = sprintf("add_test(rec, \"%s\")", text)))
}

# fixest wald() -> a test; wald() tests that the coefficients it selects are all zero
.est_from_wald <- function(w, record) {
  .est_compact(list(
    category = "restriction", name = "wald",
    statistic = .est_num(as.numeric(w$stat)), distribution = "F", df1 = as.numeric(w$df1),
    df2 = .est_num(as.numeric(w$df2)), p_value = .est_num(as.numeric(w$p)), method = "wald",
    vcov = if (!is.null(w$vcov)) .fx_vcov_type(w$vcov),
    source = list(name = "fixest", version = as.character(utils::packageVersion("fixest")),
                  call = "wald()")))
}

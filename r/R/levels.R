# Disclosure levels (spec 4.9): the most a record discloses, 1 to 5, chosen by the person who
# shares it. The marks come from inst/levels.json, which `estrec levels` writes from the
# core schema (the Python tests keep the two equal), so estrec and the validator agree.

.est_default_level <- 4L

.est_levels <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      f <- system.file("levels.json", package = "estrec")
      if (!nzchar(f)) stop("estrec's levels.json is missing; reinstall estrec", call. = FALSE)
      tab <- jsonlite::fromJSON(f, simplifyVector = FALSE)
      compile <- function(ms) lapply(ms, function(m) list(
        parts = .est_split_path(m$path), level = m$level,
        conds = lapply(m[["if"]], function(c) list(field = c$field, values = unlist(c[["in"]]), level = c$level))))
      cache <<- list(marks = compile(tab$marks), purposes = tab$purposes,
                     collection_marks = compile(tab$collection_marks),
                     min_by_kind = tab$collection_min_level_by_kind)
    }
    cache
  }
})

.est_split_path <- function(path) {
  parts <- strsplit(gsub("\\[\\*\\]", ".[*]", path), ".", fixed = TRUE)[[1]]
  parts[nzchar(parts)]
}

.est_is_index <- function(key) grepl("^\\[[0-9]+\\]$", key)

# The most specific mark for one concrete path: literal keys beat `*`, earlier keys first
.est_mark_for <- function(parts, marks) {
  best <- NULL; best_key <- ""
  for (m in marks) {
    p <- m$parts
    if (length(p) != length(parts)) next
    ok <- all(mapply(function(a, b) {
      if (a == "[*]") .est_is_index(b) else if (a == "*") !.est_is_index(b) else a == b
    }, p, parts))
    if (!ok) next
    key <- paste(ifelse(p == "*", "0", "1"), collapse = "")
    if (is.null(best) || key > best_key) { best <- m; best_key <- key }
  }
  best
}

# A field's level: its mark (and the mark's x-level-if), never below what contains it; an
# unmarked top-level member is level 5
.est_node_level <- function(parts, node, parent, marks) {
  m <- .est_mark_for(parts, marks)
  if (is.null(m)) return(if (length(parts) == 1L) 5L else parent)
  lvl <- if (is.null(m$level)) parent else m$level
  for (cnd in m$conds) {
    v <- if (is.list(node) && !is.null(names(node))) node[[cnd$field]]
    if (length(v) == 1L && v %in% cnd$values) lvl <- cnd$level
  }
  if (length(parts) > 1L) max(lvl, parent) else lvl
}

# Remove every field above `level`; returns the record and the paths removed. `marks` are
# the record marks, or the collection's for a collection's own fields
.est_apply_level <- function(rec, level, marks = .est_levels()$marks) {
  removed <- character(0)
  # an object or list that removing fields left empty goes too (one empty to begin with stays)
  walk <- function(node, parts, parent) {
    if (!is.list(node) || !length(node)) return(list(node = node, emptied = FALSE))
    named <- !is.null(names(node))
    keep <- rep(TRUE, length(node))
    for (i in seq_along(node)) {
      key <- if (named) names(node)[i] else sprintf("[%d]", i - 1L)
      sub <- c(parts, key)
      n <- .est_node_level(sub, node[[i]], parent, marks)
      if (n > level) {
        keep[i] <- FALSE
        removed[length(removed) + 1L] <<- paste(sub, collapse = ".")
      } else if (is.list(node[[i]])) {
        w <- walk(node[[i]], sub, n)
        if (w$emptied) keep[i] <- FALSE else node[i] <- list(w$node)
      }
    }
    out <- node[keep]
    if (inherits(node, "AsIs")) class(out) <- class(node)
    list(node = out, emptied = !any(keep))
  }
  rec <- walk(rec, character(0), 1L)$node
  list(record = rec, removed = gsub(".[", "[", removed, fixed = TRUE))
}

# The lowest level at which each profile estrec claims can be met: the fields its rules
# require (inference: a default vcov, 2; linear-fe and iv: the specification and FE counts, 3;
# glm: structures.numerics, 4). Checked against the validator in tests/test-fixest.R.
.est_profile_levels <- c("inference/0.1" = 2L, "linear-fe/0.1" = 3L, "iv/0.1" = 3L, "glm/0.1" = 4L)

.est_resolve_level <- function(level, purpose) {
  purposes <- .est_levels()$purposes
  for (p in purpose) if (is.null(purposes[[p]]))
    stop("purpose ", p, " isn't a purpose profile estrec knows (", paste(names(purposes), collapse = ", "),
         ")", call. = FALSE)
  need <- if (length(purpose)) max(vapply(purpose, function(p) as.integer(purposes[[p]]), 1L)) else 1L
  if (is.null(level)) level <- if (length(purpose)) need else .est_default_level
  if (length(level) != 1L || !(level %in% 1:5))
    stop("`level` must be one of 1 to 5", call. = FALSE)
  if (level < need)
    stop("disclosure level ", level, " is below the ", need, " that ", paste(purpose, collapse = ", "),
         " needs", call. = FALSE)
  as.integer(level)
}

# Cut a freshly built record to `level`: drop what's above it and the profile claims it
# breaks, declare the level, date-only times at level 1, and the history entry as the level
# allows. The caller adds the digest afterwards.
.est_at_level <- function(rec, level, purpose = NULL) {
  claimed <- unlist(rec$meta$profiles)
  if (length(purpose)) claimed <- unique(c(claimed, purpose))
  dropped <- claimed[claimed %in% names(.est_profile_levels) & .est_profile_levels[claimed] > level]
  claimed <- setdiff(claimed, dropped)
  rec$meta$profiles <- if (length(claimed)) I(claimed)
  rec$meta$disclosure <- list(level = level)
  if (level == 1L) rec$meta$created <- substr(rec$meta$created, 1L, 10L)
  rec$history <- NULL
  cut <- .est_apply_level(rec, level)
  rec <- cut$record
  if (length(dropped)) {
    if (level >= 2L) rec$meta$messages <- c(rec$meta$messages, lapply(dropped, function(p) list(
      level = "info", code = "profile_not_claimed", source = "estrec",
      message = sprintf("%s isn't claimed: disclosure level %d leaves out what it requires", p, level))))
    warning(paste(dropped, collapse = ", "), " not claimed: disclosure level ", level,
            " leaves out what ", if (length(dropped) > 1L) "they require" else "it requires", call. = FALSE)
  }
  entry <- list(when = if (level == 1L) substr(.est_now(), 1L, 10L) else .est_now())
  if (level >= 4L) entry$by <- estrec_info()
  entry$action <- "created"
  entry$level <- level
  if (level >= 2L) entry$sections <- I(setdiff(names(rec), "schema"))
  rec$history <- list(entry)
  rec
}

.est_declared_level <- function(rec) {
  l <- rec$meta$disclosure$level
  if (is.numeric(l) && length(l) == 1L && l %in% 1:5) as.integer(l)
}

# A record at a lower level (spec 4.9): a new record pointing at the original. Returns it
# unchanged when nothing in it is above `level` and it declares no higher level.
.est_reduce <- function(rec, level) {
  declared <- .est_declared_level(rec)
  cut <- .est_apply_level(rec, level)
  if (!length(cut$removed) && !is.null(declared) && declared <= level) return(rec)
  out <- cut$record
  claimed <- as.character(unlist(out$meta$profiles))
  dropped <- claimed[claimed %in% names(.est_profile_levels) & .est_profile_levels[claimed] > level]
  if (length(dropped)) {
    kept <- setdiff(claimed, dropped)
    out$meta$profiles <- if (length(kept)) I(kept)
    if (level >= 2L) out$meta$messages <- c(out$meta$messages, lapply(dropped, function(p) list(
      level = "info", code = "profile_not_claimed", source = "estrec",
      message = sprintf("%s isn't claimed: disclosure level %d leaves out what it requires", p, level))))
  }
  if (!is.null(out$meta$id)) out$meta$parent <- out$meta$id
  out$meta$id <- .est_uuid()
  out$meta$disclosure <- list(level = as.integer(level))
  entry <- list(when = if (level == 1L) substr(.est_now(), 1L, 10L) else .est_now())
  if (level >= 4L) entry$by <- estrec_info()
  entry$action <- "reduced"
  entry$level <- as.integer(level)
  entry$fields <- I(cut$removed)
  out$history <- c(out$history, list(entry))
  if (!is.null(out$meta$core_digest)) out <- .est_add_digest(out, TRUE)
  out
}

# The program in the replication package that ran the command (specification.program):
# a path relative to the package root, or list(path, line, sha256). The sha256 is computed
# when the file is found (relative to `root`) and openssl is installed.
.est_program <- function(program, root = ".") {
  if (is.null(program)) return(NULL)
  p <- if (is.character(program)) list(path = program) else as.list(program)
  if (is.null(p$path) || !is.character(p$path))
    stop("`program` needs a path: \"code/main.R\" or list(path = ..., line = ...)", call. = FALSE)
  if (!is.null(p$line)) p$line <- as.integer(p$line)
  f <- file.path(root, p$path)
  if (is.null(p$sha256) && file.exists(f) && requireNamespace("openssl", quietly = TRUE))
    p$sha256 <- .est_sha256_file(f)
  .est_compact(p[c("path", "line", "sha256")])
}

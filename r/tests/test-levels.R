# Disclosure levels (spec 4.9) and purposes. Base R, no testthat. Every record is also checked
# with the reference validator when the `estimation` CLI is on PATH or ESTREC_VALIDATOR names
# it: that is what confirms estrec's profile claims at each level.
if (!requireNamespace("fixest", quietly = TRUE)) quit(save = "no")
suppressMessages(library(fixest))
library(estrec)

set.seed(2); n <- 300
d <- data.frame(id = sample(30, n, TRUE), yr = sample(6, n, TRUE))
d$x <- rnorm(n); d$y <- d$x + rnorm(n); d$cnt <- rpois(n, exp(0.2 * d$x))

validator <- Sys.getenv("ESTREC_VALIDATOR", Sys.which("estimation"))
out <- tempfile("estrec-levels"); dir.create(out)
check <- function(rec, name) {
  path <- write_estimation(rec, file.path(out, paste0(name, ".estrec.json")))
  if (nzchar(validator)) {
    res <- system2(validator, c("validate", path), stdout = TRUE, stderr = TRUE)
    status <- attr(res, "status")
    if (!is.null(status) && status != 0) stop(name, " failed validation:\n", paste(res, collapse = "\n"))
    warn <- grep(": warning: ", res, value = TRUE)
    if (length(warn)) stop(name, " has validator warnings:\n", paste(warn, collapse = "\n"))
  }
  invisible(path)
}
quiet <- function(expr) suppressWarnings(expr)
names_of <- function(sw) vapply(sw, `[[`, "", "name")
profiles <- function(r) as.character(unclass(unlist(r[["meta"]][["profiles"]])))

f <- feols(y ~ x | id + yr, d, cluster = ~id)

# Default: level 4. R, fixest and estrec only; no environment, execution, user or host
r4 <- to_estimation(f)
check(r4, "level4")
stopifnot(r4$meta$disclosure$level == 4L,
          setequal(names_of(r4$provenance$software), c("fixest", "R", "estrec")),
          setequal(names(r4$provenance), c("software", "data")),
          r4$provenance$data[[1]]$name == "d",
          r4$history[[1]]$by$name == "estrec", r4$history[[1]]$level == 4L,
          identical(profiles(r4), c("inference/0.1", "linear-fe/0.1")))

# Level 5: everything, as before levels existed
r5 <- to_estimation(f, level = 5)
check(r5, "level5")
stopifnot(!is.null(r5$provenance$agent), !is.null(r5$provenance$environment),
          length(r5$provenance$software) >= length(r4$provenance$software))

# Level 3: the specification and FE counts, still linear-fe; no software
r3 <- to_estimation(f, level = 3)
check(r3, "level3")
stopifnot(is.null(r3$provenance), !is.null(r3$specification$formula),
          !is.null(r3$structures$fixed_effects), is.null(r3$history[[1]]$by),
          identical(profiles(r3), c("inference/0.1", "linear-fe/0.1")))

# Level 2: vcov without its clusters; linear-fe not claimed, and said so
r2 <- tryCatch(to_estimation(f, level = 2), warning = function(w) w)
stopifnot(inherits(r2, "warning"), grepl("linear-fe/0.1", conditionMessage(r2)))
r2 <- quiet(to_estimation(f, level = 2))
check(r2, "level2")
stopifnot(is.null(r2$specification), is.null(r2$structures$vcov[[1]]$cluster),
          !is.null(r2$structures$vcov[[1]]$type), !is.null(r2$tests), is.null(r2$meta$title),
          identical(profiles(r2), "inference/0.1"),
          any(vapply(r2$meta$messages, function(m) identical(m$code, "profile_not_claimed"), NA)))

# Level 1: estimates, SEs, p-values, intervals, N and df; a date, not a time
r1 <- quiet(to_estimation(f, level = 1))
check(r1, "level1")
stopifnot(setequal(names(r1), c("schema", "meta", "parameters", "metrics", "history")),
          setequal(names(r1$metrics), c("nobs", "df_residual", "conf_level")),
          nchar(r1$meta$created) == 10L, is.null(r1$meta$profiles), is.null(r1$meta$estimator),
          setequal(names(r1$history[[1]]), c("when", "action", "level")),
          all(c("estimate", "std_error", "p_value", "conf_low", "conf_high") %in% names(r1$parameters[[1]])))
stopifnot(inherits(tryCatch(add_test(r1, wald(f, keep = "x")), error = function(e) e), "error"))

# Tests on a level-2 record: no source, and no `by` in the history entry
r2t <- add_test(r2, wald(f, keep = "x"))
check(r2t, "level2-test")
last <- r2t$history[[length(r2t$history)]]
stopifnot(is.null(last$by), is.null(r2t$tests[[length(r2t$tests)]]$source))

# GLM: glm/0.1 needs structures.numerics (level 4)
g <- fepois(cnt ~ x | id, d)
check(to_estimation(g), "glm4")
g3 <- quiet(to_estimation(g, level = 3))
check(g3, "glm3")
stopifnot(!("glm/0.1" %in% profiles(g3)))

# IV keeps iv/0.1 at level 3
d$z <- d$x + rnorm(n); d$y2 <- d$y + d$x
iv <- feols(y2 ~ 1 | id | x ~ z, d)
iv3 <- to_estimation(iv, level = 3)
check(iv3, "iv3")
stopifnot("iv/0.1" %in% profiles(iv3))

# A purpose: dcas/0.1 sets level 4 and is claimed; with the locator and data name it validates
pub <- list(locator = list(table = "2", column = "1", label = "Table 2, column (1)"),
            citation = list(type = "article-journal", title = "An illustrative paper"),
            status = "submitted", replication_package = list(doi = "10.0000/x"))
prog <- file.path(out, "main.R"); writeLines("feols(y ~ x | id + yr, d)", prog)
ra <- to_estimation(f, purpose = "dcas/0.1", publication = pub,
                    program = list(path = "main.R", line = 1),
                    data_info = list(name = "Illustrative panel", checksum = list(
                      algorithm = "sha256", value = strrep("ab", 32), of = "file"),
                      publication = list(citation = list(type = "dataset", title = "Illustrative panel"))))
check(ra, "dcas")
stopifnot(ra$meta$disclosure$level == 4L, "dcas/0.1" %in% profiles(ra),
          ra$specification$program$path == "main.R", ra$specification$program$line == 1L)
old <- setwd(out)
rp <- to_estimation(f, level = 5, program = "main.R")
setwd(old)
stopifnot(is.null(rp$specification$program$sha256) || nchar(rp$specification$program$sha256) == 64L)
stopifnot(inherits(tryCatch(to_estimation(f, purpose = "dcas/0.1", level = 3), error = function(e) e), "error"),
          inherits(tryCatch(to_estimation(f, purpose = "nope/0.1"), error = function(e) e), "error"),
          inherits(tryCatch(to_estimation(f, level = 6), error = function(e) e), "error"))

cat("estrec level tests passed", if (nzchar(validator)) "(records validated)", "\n")

# Collections (spec 11.7)
coll_check <- function(path) {
  if (!nzchar(validator)) return(invisible())
  res <- system2(validator, c("validate", path), stdout = TRUE, stderr = TRUE)
  status <- attr(res, "status")
  if (!is.null(status) && status != 0) stop(path, " failed validation:\n", paste(res, collapse = "\n"))
  bad <- grep(": (warning|error): .*level", res, value = TRUE)
  if (length(bad)) stop(paste(bad, collapse = "\n"))
}
cdir <- tempfile("estrec-coll"); dir.create(cdir)
# fits: written at the default level 4, declared on the collection
p <- file.path(cdir, "paper.estrec-collection.json")
write_collection(list(a = f, b = feols(y ~ x | id, d)), p, kind = "paper",
                 locators = list("Table 1, col. (1)", "Table 1, col. (2)"),
                 publication = list(citation = list(type = "report", title = "A paper")))
coll_check(p)
pc <- jsonlite::fromJSON(p, simplifyVector = FALSE)
stopifnot(pc$meta$disclosure$level == 4L, pc$members[[1]]$record$meta$disclosure$level == 4L)
# level-5 records lowered to 2: new records pointing at the originals
recs <- list(to_estimation(f, level = 5), to_estimation(f, level = 5, vcov = list("iid")))
p2 <- file.path(cdir, "batch2.estrec-collection.json")
quiet(write_collection(recs, p2, kind = "batch", level = 2))
coll_check(p2)
b2 <- jsonlite::fromJSON(p2, simplifyVector = FALSE)
stopifnot(b2$meta$disclosure$level == 2L,
          identical(b2$members[[1]]$record$meta$parent, recs[[1]]$meta$id),
          b2$members[[1]]$id == b2$members[[1]]$record$meta$id,
          is.null(b2$members[[1]]$record$provenance), is.null(b2$history[[1]]$by))
# records only, no level: kept as they are
p3 <- file.path(cdir, "batch5.estrec-collection.json")
write_collection(recs, p3, kind = "batch")
b3 <- jsonlite::fromJSON(p3, simplifyVector = FALSE)
stopifnot(is.null(b3$meta$disclosure), b3$members[[1]]$id == recs[[1]]$meta$id)
# a session at level 4: the session's times and clients and the worker events left out
s5 <- lapply(recs, function(r) { r$provenance$execution$session <- "s1"; r })
ev <- list(list(when = "2026-11-05T10:00:00Z", type = "fit", member = s5[[1]]$meta$id),
           list(when = "2026-11-05T10:00:01Z", type = "worker_lost", detail = list(host = "node7")),
           list(when = "2026-11-05T10:00:02Z", type = "fit", member = s5[[2]]$meta$id))
p4 <- file.path(cdir, "session.estrec-collection.json")
quiet(write_collection(s5, p4, kind = "session", level = 4, events = ev,
                       session = list(id = "s1", status = "closed", started = "2026-11-05T09:59:00Z",
                                      clients = list(list(language = "R", host = "laptop")))))
coll_check(p4)
s4 <- jsonlite::fromJSON(p4, simplifyVector = FALSE)
stopifnot(is.null(s4$session$started), is.null(s4$session$clients), length(s4$events) == 2L,
          s4$events[[1]]$member == s4$members[[1]]$id)
stopifnot(inherits(tryCatch(write_collection(s5, p4, kind = "session", level = 3), error = function(e) e), "error"))
cat("estrec collection level tests passed\n")

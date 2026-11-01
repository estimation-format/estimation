# Base-R tests of collections (no testthat). Collections are also checked with the reference
# validator when the `estimation` CLI is on PATH or ESTREC_VALIDATOR names it, and the
# canonical JSON is compared with the Python reference when ESTREC_PYTHON names a Python
# with estimation_format installed.
library(estrec)
canon <- estrec:::.est_canonical_json
esn <- estrec:::.est_es_number

# RFC 8785 numbers (ECMAScript): shortest round-trip digits, exponent outside [1e-6, 1e21)
stopifnot(identical(vapply(c(1e21, 1e-7, 1e-6, 4.5, 2e-3, 5e-324, -0, 333333333.33333329,
                             1.7976931348623157e308, 295147905179352830000), esn, ""),
                    c("1e+21", "1e-7", "0.000001", "4.5", "0.002", "5e-324", "0",
                      "333333333.3333333", "1.7976931348623157e+308", "295147905179352830000")))
# R's own parser misrounds this one; the shortest form must still be found
x <- jsonlite::fromJSON("[1.3664942854469041e+27]")
stopifnot(identical(esn(x), "1.366494285446904e+27"))
# strings, empty objects vs arrays, keys by UTF-16 code units
j <- estrec:::.est_jcs(jsonlite::fromJSON(
  '{"b":1,"a":{},"\\u00e9":[],"\\ud83d\\ude00":2,"\\ufb33":3,"s":"a\\"b\\\\c\\nd\\u0001"}',
  simplifyVector = FALSE))
stopifnot(identical(j, enc2utf8(paste0('{"a":{},"b":1,"s":"a\\"b\\\\c\\nd\\u0001","é":[],',
                                       '"\U0001F600":2,"דּ":3}'))))

validator <- Sys.getenv("ESTREC_VALIDATOR", Sys.which("estimation"))
python <- Sys.getenv("ESTREC_PYTHON")
out <- tempfile("estrec-coll"); dir.create(out)
validate <- function(path) {
  if (!nzchar(validator)) return(invisible(NULL))
  res <- system2(validator, c("validate", path), stdout = TRUE, stderr = TRUE)
  status <- attr(res, "status")
  if (!is.null(status) && status != 0) stop(path, " failed validation:\n", paste(res, collapse = "\n"))
  # the collection's own warnings (its members' are the record writer's business)
  own <- grep(": warning: ", res, value = TRUE)
  own <- own[!grepl(": warning: members\\[[0-9]+\\]\\.record", own)]
  if (length(own)) stop(path, " has warnings:\n", paste(own, collapse = "\n"))
  invisible(res)
}
read <- function(path) jsonlite::fromJSON(path, simplifyVector = FALSE)
has_openssl <- requireNamespace("openssl", quietly = TRUE)

if (requireNamespace("fixest", quietly = TRUE)) {
  suppressMessages(library(fixest))
  f1 <- feols(mpg ~ wt | cyl, mtcars)
  f2 <- feols(mpg ~ wt + hp | cyl, mtcars, vcov = "hetero")
  fm <- feols(c(mpg, qsec) ~ wt, mtcars)

  # to_estimation on a plain list: one record per fit, multis flattened, names kept
  recs <- to_estimation(list(base = f1, full = f2, multi = fm))
  stopifnot(length(recs) == 4, identical(names(recs), c("base", "full", "multi.1", "multi.2")),
            all(vapply(recs, is_estimation_record, logical(1))))
  stopifnot(identical(to_estimation(recs[[1]]), recs[[1]]))   # a record passes through
  stopifnot(length(to_estimation(list(f1, recs[[2]]))) == 2)   # fits and records mixed

  # A paper: labels from names, locators as strings and lists, the citation
  pub <- list(citation = list(type = "report", title = "An illustrative working paper",
                              DOI = "10.0000/example"))
  p <- file.path(out, "paper.estimation-collection.json")
  write_collection(list(base = f1, full = f2), p, kind = "paper", publication = pub,
                   locators = list("Table 2, col. 1", list(table = "2", column = "2")),
                   title = "Table 2")
  validate(p)
  coll <- read(p)
  stopifnot(coll$schema == "estimation-collection/0.1", coll$meta$kind == "paper",
            length(coll$members) == 2, coll$members[[1]]$label == "base",
            coll$members[[1]]$locator$label == "Table 2, col. 1",
            coll$members[[2]]$locator$column == "2",
            identical(coll$members[[1]]$id, coll$members[[1]]$record$meta$id),
            is.null(coll$members[[1]]$record$publication))     # locators stay in the collection
  if (has_openssl) {
    # the hash is over the record as it reads back from the file
    stopifnot(identical(coll$members[[2]]$sha256,
                        estrec:::.est_sha256(canon(coll$members[[2]]$record))))
  } else {
    stopifnot(is.null(coll$members[[1]]$sha256))
  }

  # A record appearing twice is one member with several locators
  q <- file.path(out, "twice.estimation-collection.json")
  write_collection(list(f1), q, kind = "paper", publication = pub,
                   locators = list(c("Table 2, col. 1", "Table A1, col. 1")))
  validate(q)
  stopifnot(length(read(q)$members[[1]]$locators) == 2)
  stopifnot(inherits(try(write_collection(list(recs[[1]], recs[[1]]), q), silent = TRUE),
                     "try-error"))

  # A batch in a members file: one record per line, listed in attachments
  b <- file.path(out, "batch.estimation-collection.json")
  paths <- write_collection(fm, b, kind = "batch", members = "jsonl")
  stopifnot(length(paths) == 2, basename(paths[2]) == "batch.members.jsonl")
  validate(b)
  coll <- read(b)
  lines <- readLines(paths[2], encoding = "UTF-8")
  stopifnot(length(lines) == 2, coll$attachments[[1]]$role == "members",
            coll$attachments[[1]]$rows == 2,
            all(vapply(coll$members, function(m) m$attachment == "members", logical(1))),
            is.null(coll$members[[1]]$record))
  stopifnot(identical(jsonlite::fromJSON(lines[1], simplifyVector = FALSE)$meta$id,
                      coll$members[[1]]$id))

  # A session: its id on every member's provenance, a fit event per member
  rs <- lapply(recs[1:2], function(r) { r$provenance$execution$session <- "s-1"; r })
  ev <- list(list(when = "2026-11-01T12:00:00Z", type = "data_loaded", detail = list(rows = 32L)),
             list(when = "2026-11-01T12:00:01Z", type = "fit", member = rs[[1]]$meta$id),
             list(when = "2026-11-01T12:00:02Z", type = "fit", member = rs[[2]]$meta$id))
  s <- file.path(out, "session.estimation-collection.json")
  write_collection(rs, s, kind = "session", events = ev,
                   session = list(id = "s-1", status = "closed"))
  validate(s)
  stopifnot(length(read(s)$events) == 3)

  # The canonical JSON equals the Python reference's on the same records
  if (nzchar(python)) {
    for (path in c(p, b)) {
      code <- paste0("import json,sys; from estimation_format import read_collection, iter_members; ",
                     "from estimation_format.records import canonical_json, to_json; ",
                     "c = read_collection(sys.argv[1], nonfinite='string'); ",
                     "[sys.stdout.buffer.write(canonical_json(to_json(r)) + b'\\n') ",
                     "for _, _, r in iter_members(c, sys.argv[2])]")
      py <- system2(python, c("-c", shQuote(code), shQuote(path), shQuote(dirname(path))),
                    stdout = TRUE)
      coll <- read(path)
      rr <- if (!is.null(coll$members[[1]]$record)) lapply(coll$members, `[[`, "record")
            else lapply(readLines(sub("estimation-collection.json$", "members.jsonl", path),
                                  encoding = "UTF-8"),
                        jsonlite::fromJSON, simplifyVector = FALSE)
      stopifnot(identical(enc2utf8(py), vapply(rr, canon, "")))
    }
  }
}

# Without fixest: records given directly
r <- list(schema = "estimation/0.1",
          meta = list(id = "6f1c0000-0000-4000-8000-0000000000aa", created = "2026-11-01T00:00:00Z",
                      status = "ok"),
          parameters = list(list(term = "x", estimate = 0.1, std_error = 1 / 3)))
o <- file.path(out, "other.estimation-collection.json")
write_collection(list(only = r), o, kind = "other", hash = FALSE)
validate(o)
stopifnot(read(o)$members[[1]]$label == "only")
cat("collection tests passed\n")

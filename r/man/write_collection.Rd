\name{write_collection}
\alias{write_collection}
\title{Write estimation records as a collection}
\description{
Writes a set of records as one \code{estimation-collection/0.1} file (spec section 11): a
paper's results with where each appears (\code{kind = "paper"}), a session or replication
with its timeline of \code{events}, or a batch of runs. The records are embedded whole and
never changed; the collection adds labels, locators and what is true of the set.

With \code{members = "jsonl"}, or when the file would pass 16 MB, the records go to a JSON
Lines members file next to it (\code{<name>.members.jsonl}, one record per line), listed in
the collection's \code{attachments}.

Each member carries the SHA-256 of its record's RFC 8785 canonical JSON, which shows which
version of the record the collection holds, when the \pkg{openssl} package is installed.
}
\usage{
write_collection(x, path, kind = c("paper", "session", "replication", "batch", "other"),
  labels = NULL, locators = NULL, publication = NULL, session = NULL, events = NULL,
  provenance = NULL, title = NULL, notes = NULL, tags = NULL,
  members = c("embed", "jsonl"), hash = NULL, level = NULL, ...)
}
\arguments{
\item{x}{a list of fitted models or records (converted as by \code{\link{to_estimation}}), or
one fit such as a \code{fixest_multi}.}
\item{path}{the file to write, \code{<name>.estimation-collection.json}.}
\item{kind}{what the collection is: it sets which parts a validator expects.}
\item{labels}{the collection's name for each member; by default the names of \code{x}.}
\item{locators}{where each record appears in \code{publication}, one entry per record: a
label string (\code{"Table 3, col. 9"}), a locator list (\code{list(table = "3", column =
"9")}), several of these (the result appears more than once), or \code{NULL}. Locators stay
in the collection; the records are not changed.}
\item{publication}{the paper: a \code{publication} list with \code{citation} (CSL-JSON).}
\item{session, provenance}{the session's own \code{session} and \code{provenance} sections.}
\item{events}{a list of events, each \code{list(when, type, member, detail, message)}.}
\item{title, notes, tags}{user labels for \code{meta}.}
\item{members}{\code{"embed"} the records in the file, or put them in a \code{"jsonl"}
members file.}
\item{hash}{write member hashes: by default when \pkg{openssl} is installed.}
\item{level}{disclosure level of the collection, 1 to 5 (spec 4.9, 11.7). Fits are converted
at it (default 4, as \code{to_estimation}); a record above it is lowered (a new record with
\code{meta.parent}, and the events that name it follow); the collection's own fields above it
(session times and clients, events about workers and clients, provenance below 4) are left
out. With only records and no \code{level}, nothing is declared or changed. A session or
replication collection needs level 4 or more.}
\item{...}{passed to \code{\link{to_estimation}} for fitted models.}
}
\value{The paths written (the collection, then any members file), invisibly.}
\examples{
if (requireNamespace("fixest", quietly = TRUE)) {
  fits <- list(base = fixest::feols(mpg ~ wt | cyl, mtcars),
               full = fixest::feols(mpg ~ wt + hp | cyl, mtcars))
  write_collection(fits, tempfile(fileext = ".estimation-collection.json"),
                   locators = c("Table 2, col. 1", "Table 2, col. 2"),
                   publication = list(citation = list(type = "report", title = "A working paper")))
}
}

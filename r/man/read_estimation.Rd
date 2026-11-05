\name{read_estimation}
\alias{read_estimation}
\alias{read_collection}
\title{Read estimation records and collections}
\description{
\code{read_estimation} reads one record (\code{*.estimation.json}), or every record in a
folder. \code{read_collection} reads an \code{estimation-collection/0.1} file and returns its
member records, whether embedded or in a JSON Lines members file.

Records are kept as written and get class \code{estimation_record}, which prints a summary and
has \code{tidy} and \code{glance} methods (see \code{\link{tidy.estimation_record}}), so table
packages such as \pkg{modelsummary} take them directly:
\code{modelsummary::modelsummary(read_collection("table2.estimation-collection.json"))}.
}
\usage{
read_estimation(path)
read_collection(path)
}
\arguments{
\item{path}{for \code{read_estimation}, a record file or a folder of them; for
\code{read_collection}, a collection file.}
}
\value{
\code{read_estimation}: a record, or for a folder a list of records named by file stem.
\code{read_collection}: a list of records in the collection's order, named by member label
(else id). Each record carries its member entry (label, locators) as attribute
\code{"member"}, and the list carries the collection without its records as attribute
\code{"collection"}.
}
\seealso{\code{\link{write_estimation}}, \code{\link{write_collection}}}
\examples{
\dontrun{
r <- read_estimation("fit.estimation.json")
r                       # quick view
generics::tidy(r, vcov = "iid")
tab <- read_collection("table2.estimation-collection.json")
modelsummary::modelsummary(tab, stars = TRUE)
}
}

\name{write_estimation}
\alias{write_estimation}
\title{Write estimation records as JSON}
\description{
Writes one record per file, with doubles to 17 significant digits so they round-trip
exactly. With several records (a \code{fixest_multi}), \code{path} is numbered:
\code{fit.estrec.json} becomes \code{fit-1.estrec.json}, \code{fit-2.estrec.json}, ...
}
\usage{
write_estimation(x, path, ...)
}
\arguments{
\item{x}{a fitted model, a record, or a list of records.}
\item{path}{the file to write.}
\item{...}{passed to \code{\link{to_estimation}} when \code{x} is a fitted model.}
}
\value{The paths written, invisibly.}
\examples{
if (requireNamespace("fixest", quietly = TRUE)) {
  fit <- fixest::feols(mpg ~ wt | cyl, mtcars)
  write_estimation(fit, tempfile(fileext = ".estrec.json"))
}
}

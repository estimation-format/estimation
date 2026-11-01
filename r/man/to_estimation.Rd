\name{to_estimation}
\alias{to_estimation}
\alias{to_estimation.fixest}
\alias{to_estimation.fixest_multi}
\alias{to_estimation.list}
\alias{to_estimation.default}
\alias{is_estimation_record}
\title{Convert a fitted model to an estimation record}
\description{
Returns the record as a list, in the \code{estimation} format (\code{estimation/0.1}):
parameters, metrics, vcov with its small-sample correction, sample drops by reason, fixed
effects, and provenance. A \code{fixest_multi} gives a list of records, one per model.

A plain list of fits (or records) gives a flat list of records, named as the list is; a
\code{fixest_multi} element contributes one record per model, named \code{<name>.1},
\code{<name>.2}, ... A record passes through unchanged.
}
\usage{
to_estimation(fit, ...)

\method{to_estimation}{fixest}(fit, data = NULL, vcov = NULL, conf_level = 0.95,
  tests = NULL, title = NULL, notes = NULL, tags = NULL, publication = NULL, call = TRUE,
  identifying = TRUE, digest = NULL, ...)

is_estimation_record(x)
}
\arguments{
\item{fit}{a fitted model: a \code{fixest} \code{feols} (OLS or IV), \code{feglm} or \code{fepois} fit, or a \code{fixest_multi};
or a list of them.}
\item{data}{the data the model was fitted on, to split sample drops by reason (missing,
non-finite, zero weights, singletons and, for GLMs, separated). By default it is recovered from the fit's call
environment; without it, drops are recorded as \code{other}.}
\item{vcov}{\code{NULL} for the fit's own vcov, or a list of \code{vcov} arguments for
\code{summary.fixest} (e.g. \code{list("hetero", ~firm)}). Each is recorded; the first is
the default and gives the parameters' standard errors.}
\item{conf_level}{confidence level of \code{conf_low}/\code{conf_high}.}
\item{tests}{test results to add, one or a \code{list()} of them, as for \code{\link{add_test}}
(\code{fixest::wald()}, \code{marginaleffects::hypotheses()}, ...). The record always has
fixest's joint Wald test of the coefficients, and for IV the first-stage,
weak-identification, endogeneity and overidentification tests.}
\item{title, notes, tags}{user labels for \code{meta}.}
\item{publication}{optional \code{publication} section: where the result appears in a paper.}
\item{call}{include the call as written.}
\item{identifying}{include the user, host and command line (removable later with
\code{estimation redact}).}
\item{digest}{write \code{meta.core_digest} (spec 7.2). By default it is written when the
\code{openssl} package is installed; \code{TRUE} requires it, \code{FALSE} leaves it out.}
\item{x}{an object.}
\item{...}{passed to methods.}
}
\value{A record (a list), or a list of records.}
\examples{
if (requireNamespace("fixest", quietly = TRUE)) {
  fit <- fixest::feols(mpg ~ wt | cyl, mtcars)
  rec <- to_estimation(fit, vcov = list("hetero", "iid"))
  rec$parameters[[1]]$std_error
  recs <- to_estimation(list(base = fit, full = fixest::feols(mpg ~ wt + hp | cyl, mtcars)))
  names(recs)
}
}

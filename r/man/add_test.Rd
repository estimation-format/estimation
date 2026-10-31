\name{add_test}
\alias{add_test}
\title{Add a hypothesis test to an estimation record}
\description{
Appends one test to the record's \code{tests} (spec 4.8) and a \code{history} entry. A test
given as text is computed from the record's own parameters and vcov, so it always matches
the vcov the record holds. \code{tests} is append-only and outside the core digest.
}
\usage{
add_test(record, test, vcov = NULL, label = NULL, category = NULL, id = NULL,
  tags = NULL, origin = "postestimation", by = estrec_info())
}
\arguments{
\item{record}{an estimation record (from \code{\link{to_estimation}}).}
\item{test}{a hypothesis as text: restrictions with \code{=}, separated by commas
(\code{"x = x2"}, \code{"x = 0, x2 = 0"}, \code{"2*x - x2 = 1"}), give a Wald test, F with
the vcov's \code{df_t} (chi-squared when it has none); an expression without \code{=}
(\code{"x + x2"}) gives a linear combination: estimate, standard error, interval and t test
against 0. Terms are \code{parameters[*].term}; quote non-syntactic names with backticks.
Or a \code{fixest::wald()} result, or a test object (a list with \code{name} and
\code{statistic} or \code{p_value}).}
\item{vcov}{the \code{structures.vcov} entry to use: a type (\code{"HC1"}) or
\code{list(type =, cluster =)}; \code{NULL} for the default.}
\item{label, tags}{the user's label and tags.}
\item{category}{overrides the category (\code{restriction}, \code{linear_combination}).}
\item{id}{the test's id; by default \code{t<n>}.}
\item{origin}{\code{"postestimation"} (default) or \code{"estimation"}.}
\item{by}{the tool recorded in \code{history}.}
}
\value{The record, with the test appended.}
\examples{
if (requireNamespace("fixest", quietly = TRUE)) {
  fit <- fixest::feols(mpg ~ wt + hp | cyl, mtcars)
  rec <- to_estimation(fit, vcov = list("iid", "hetero"))
  rec <- add_test(rec, "wt = 0, hp = 0")
  rec <- add_test(rec, "wt + 100*hp", vcov = "HC1", label = "wt plus 100 hp")
  rec$tests[[3]]$estimate
}
}

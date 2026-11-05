\name{add_test}
\alias{add_test}
\alias{as_estimation_test}
\alias{as_estimation_test.default}
\alias{as_estimation_test.list}
\alias{as_estimation_test.htest}
\alias{as_estimation_test.anova}
\alias{as_estimation_test.data.frame}
\title{Record a hypothesis test result in an estimation record}
\description{
\code{add_test} appends the result of a test to the record's \code{tests} (spec 4.8), with a
\code{history} entry. estrec doesn't run tests: run the test with the function you use, and
pass its result. \code{tests} is append-only and outside the core digest.

\code{as_estimation_test} reads a test result into test objects. It is a generic: to record
the results of another function, write a method for its class that returns a list of test
objects (each a list with \code{name} and \code{statistic} or \code{p_value}, and as many of
the spec's fields as the result gives).
}
\usage{
add_test(record, test, label = NULL, category = NULL, hypothesis = NULL, vcov = NULL,
  id = NULL, tags = NULL, origin = "postestimation", by = estrec_info())

as_estimation_test(x, record = NULL, call = NULL, expr = NULL, env = parent.frame(), ...)
}
\arguments{
\item{record}{an estimation record (from \code{\link{to_estimation}}).}
\item{test, x}{a test result. Methods are included for:
\itemize{
\item a \code{fixest::wald()} result. \code{wald()} doesn't return which terms it tested, so
they are read from the call's \code{keep} and \code{drop}, matched against the record's terms;
\item \code{marginaleffects::hypotheses()}, or any data frame with broom-style columns
(\code{estimate}, \code{std.error}, \code{statistic}, \code{p.value}, \code{conf.low},
\code{conf.high}): one test per row;
\item an \code{anova} comparison table (\code{anova(m1, m2)}, \code{car::linearHypothesis()},
\code{lmtest::waldtest()}, \code{lmtest::lrtest()}): the test in its last row;
\item an \code{htest} (\code{t.test()}, \code{chisq.test()}, ...);
\item a test object, or a list of them, added as is.
}}
\item{label, tags}{the user's label and tags.}
\item{category}{what the test is about (\code{restriction}, \code{pretrend}, ...).}
\item{hypothesis}{the hypothesis as text, when the result doesn't carry it.}
\item{vcov}{the \code{structures.vcov} entry the test used, when the result doesn't say: a
type (\code{"HC1"}) or \code{list(type =, cluster =)}. Recorded only.}
\item{id}{the test's id; by default \code{t<n>}.}
\item{origin}{\code{"postestimation"} (default) or \code{"estimation"}.}
\item{by}{the tool recorded in \code{history}.}
\item{call, expr, env}{for methods: the call that made the result, as text and unevaluated,
and the environment to evaluate its arguments in.}
\item{...}{for methods.}
}
\value{\code{add_test}: the record, with the tests appended. A record written at disclosure
level 1 takes no tests (they are level 2); below level 4 a test's \code{source} and the
history entry's \code{by} are left out. \code{as_estimation_test}: a list of test objects.}
\examples{
if (requireNamespace("fixest", quietly = TRUE)) {
  fit <- fixest::feols(mpg ~ wt + hp | cyl, mtcars)
  rec <- to_estimation(fit)
  rec <- add_test(rec, fixest::wald(fit, keep = "^(wt|hp)$", print = FALSE),
                  label = "both slopes")
  rec$tests[[2]]$hypothesis$terms
}
# Results of your own test function: a method returning test objects
as_estimation_test.my_test <- function(x, ...)
  list(list(name = "wald", statistic = x$W, distribution = "chi2", df = x$k, p_value = x$p))
}

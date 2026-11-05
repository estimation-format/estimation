\name{tidy.estimation_record}
\alias{tidy.estimation_record}
\alias{glance.estimation_record}
\alias{print.estimation_record}
\title{Views of an estimation record: tidy, glance and print}
\description{
\code{tidy} gives the record's parameters with broom's column names (\code{term},
\code{estimate}, \code{std.error}, \code{statistic}, \code{p.value}, \code{conf.low},
\code{conf.high}, and \code{response} or \code{component} when the record has them).
\code{glance} gives one row of its metrics, the default vcov (\code{vcov.type}) and one
\code{"FE: <name>"} column per fixed effect. The methods are registered on \pkg{generics}
when it is loaded, which is what \pkg{modelsummary} and \pkg{broom} use.

By default \code{tidy} returns the parameters as written, which come from the record's
default vcov. With \code{vcov}, it computes them again from another vcov in the record:
standard errors from that matrix's diagonal, with t tests on its \code{df_t}, or normal tests
when it has none.
}
\usage{
\method{tidy}{estimation_record}(x, conf.int = TRUE, conf.level = NULL, vcov = NULL,
  component = NULL, dropped = FALSE, ...)
\method{glance}{estimation_record}(x, vcov = NULL, ...)
\method{print}{estimation_record}(x, digits = 4, ...)
}
\arguments{
\item{x}{a record from \code{\link{read_estimation}} or \code{\link{read_collection}}.}
\item{conf.int}{include the confidence interval.}
\item{conf.level}{the interval's level; by default the record's \code{metrics$conf_level}.}
\item{vcov}{which vcov: \code{NULL} for the default, a position, a \code{type} (\code{"iid"},
\code{"HC1"}, \code{"CRV1"}, ...), or the cluster variables (\code{"firm"},
\code{"firm & year"}, \code{"by: firm"}).}
\item{component}{\code{NULL} for the main model (rows with no \code{component}), a
component name such as \code{"first_stage"}, or \code{"all"}.}
\item{dropped}{keep collinear and reference terms, which have no estimate.}
\item{digits}{significant digits.}
\item{...}{unused.}
}

#' Extract estimates and statistics from a single model
#' @param model object type with an available `tidy` method.
#' @inheritParams modelsummary
#' @return data.frame with side-by-side model summaries
#' @noRd
extract_estimates <- function(
  model,
  estimate   = "estimate",
  statistic  = "std.error",
  vcov       = NULL,
  conf_level = .95,
  fmt        = "%.3f",
  stars      = FALSE,
  ...) {

  # conf.int to glue
  estimate_glue <- ifelse(
    estimate == "conf.int",
    "[{conf.low}, {conf.high}]",
    estimate)

  statistic_glue <- ifelse(
    statistic == "conf.int",
    "[{conf.low}, {conf.high}]",
    statistic)

  # estimate to glue
  estimate_glue <- ifelse(
    grepl("\\{", estimate_glue),
    estimate_glue,
    sprintf("{%s}", estimate_glue))
    
  # statistics to glue
  if (!is.null(vcov) &&     # don't add parentheses
      is.character(vcov) && # to manual strings
      length(vcov) > 1) {   # of length greater than 1 (i.e., robust shortcuts)
    statistic_glue <- ifelse(
      grepl("\\{", statistic_glue),
      statistic_glue,
      sprintf("{%s}", statistic_glue))
  } else {
    statistic_glue <- ifelse(
      grepl("\\{", statistic_glue),
      statistic_glue,
      sprintf("({%s})", statistic_glue))
  }

  # combine estimate and statistics
  estimate_glue <- c(estimate_glue, statistic_glue)
  
  # extract estimates using broom or parameters
  if (any(grepl("conf", estimate_glue))) {
    est <- get_estimates(model, conf_level=conf_level, ...)
  } else {
    est <- get_estimates(model, conf_level=NULL, ...)
  }
  
  # estimate override
  flag1 <- !is.null(vcov)
  flag2 <- isFALSE(all.equal(vcov, stats::vcov))
  flag3 <- !is.character(vcov)
  flag4 <- is.character(vcov) && length(vcov) == 1 && !vcov %in% c("classical", "iid", "constant")
  flag5 <- is.character(vcov) && length(vcov) > 1

  if (flag1 && (flag2 || flag3 || flag4 || flag5)) {

    # extract overriden estimates
    so <- extract_vcov(
      model,
      vcov=vcov,
      conf_level=conf_level)

    if (!is.null(so) && nrow(est) == nrow(so)) {
      # keep only columns that do not appear in so
      est <- est[, c('term', base::setdiff(colnames(est), colnames(so))), drop = FALSE]
      # merge vcov and estimates
      est <- merge(est, so, by="term", sort=FALSE)

    } 
  }

  # tidy_custom
  est_custom <- tidy_custom(model)
  sanity_tidy(est, est_custom, estimate, statistic, class(model)[1])
  if (!is.null(est_custom)) {
    for (n in colnames(est_custom)) {
      est[[n]] <- est_custom[[n]]
    }
  }

  # group coefficients
  if (anyDuplicated(est$term) > 0) {
    # broom.mixed `group` column
    if ("group" %in% colnames(est)) {
      est$term <- ifelse(is.na(est$group), 
                         est$term, 
                         paste0(est$group, " | ", est$term))
    }
    # nnet::multinom `y.level` column
    if ("y.level" %in% colnames(est)) {
      est$term <- ifelse(is.na(est$y.level), 
                         est$term, 
                         paste0(est$y.level, " | ", est$term))
    }
  }


  # term must be a character (not rounded with decimals when integer)
  est$term <- as.character(est$term)


  # stars (before rounding)
  # compute stars if: 
  #   a) stars is not FALSE
  #   b) {stars} is in glue string 
  # paste stars if:
  #   a) stars is not FALSE and is not a glue string
  is_star <- !isFALSE(stars) || isTRUE(any(grepl("\\{stars\\}", estimate_glue)))
  is_glue <- grepl("\\{", estimate)
  if (is_star) {
    # glue string can include stars even if stars=FALSE 
    if (isFALSE(stars)) {
      stars <- TRUE
    }
    if (!'p.value' %in% colnames(est)) {
      stop('To use the `stars` argument, the `tidy` function must produce a column called "p.value"')
    }
    est$stars <- make_stars(est$p.value, stars)
  }
  if (isTRUE(is_star) && isFALSE(is_glue)) {
    estimate_glue[1] <- paste0(estimate_glue[1], "{stars}")
  }


  # round everything
  for (n in colnames(est)) {
    est[[n]] <- rounding(est[[n]], fmt)
  }

  # extract estimates (there can be several)
  for (i in seq_along(estimate_glue)) {
    s <- estimate_glue[i]
    est[[paste0("modelsummary_tmp", i)]] <- as.character(glue::glue_data(est, s))
    # avoid empty parentheses for NAs
    est[[paste0("modelsummary_tmp", i)]][est[[s]] == ""] <- ""
  }


  # subset columns
  cols <- c('term', paste0('modelsummary_tmp', seq_along(estimate_glue)))
  est <- est[, cols, drop = FALSE]

  # reshape to vertical
  # sort by statistic to have se below coef, but don't sort terms
  # use factor hack to preserve order with weird names like cor__(Inter.)
  # especially important for broom.mixed models 
  est$term <- factor(est$term, unique(est$term))
  est <- stats::reshape(
    data.frame(est),
    varying       = grep("modelsummary_tmp\\d+$", colnames(est), value=TRUE),
    times         = grep("modelsummary_tmp\\d+$", colnames(est), value=TRUE),
    v.names       = "value",
    timevar       = "statistic",
    direction     = "long",
    new.row.names = 1:1000)
  est$id <- NULL

  # sort then convert back to character
  est <- est[order(est$term, est$statistic),]
  est$term <- as.character(est$term)

  # drop empty rows (important for broom.mixed which produces group
  # estimates without standard errors)
  est <- est[est$value != "", ]

  # output
  return(est)
}

#' Extract model estimates. A mostly internal function with some potential uses
#' outside.
#'
#' @inheritParams modelsummary
#' @param model a single model object
#' @export
get_estimates <- function(model, conf_level=.95, ...) {

  if (is.null(conf_level)) {
    conf_int=FALSE
  } else {
    conf_int=TRUE
  }

  flag <- function(x) {
    inherits(x, "data.frame") &&
    nrow(x) > 0 &&
    "term" %in% colnames(x)
  }

  # generics first
  est <- suppressWarnings(try(
    generics::tidy(model, conf.int=conf_int, conf.level=conf_level, ...), silent=TRUE))
  if (flag(est)) return(est)

  # broom second 
  # can't use generics::tidy here otherwise broom only gets loaded the second
  # time modelsummary is called, and the first attempt fails.
  est <- suppressWarnings(try(
    broom::tidy(model, conf.int=conf_int, conf.level=conf_level, ...), silent=TRUE))
  if (flag(est)) return(est)

  # parameters third
  est <- suppressWarnings(try(
    tidy_easystats(model, ci=conf_level, ...), silent=TRUE))
  if (flag(est)) return(est)

  # broom.mixed fourth
  if (check_dependency("broom.mixed")) {
    est <- suppressWarnings(try(
      broom.mixed::tidy(model, conf.int=TRUE, conf.level=conf_level, ...), silent=TRUE))
  }
  if (flag(est)) return(est)

  stop(sprintf('Cannot extract the required information from models of class "%s". Consider installing `broom.mixed`, or any other package that includes `tidy` and `glance` methods appropriate for this model type. Alternatively, you can easily define your own methods by following the instructions on the `modelsummary` website: https://vincentarelbundock.github.io/modelsummary/articles/newmodels.html', class(model)[1]))

}
 

#' Entropy-based Filters
#'
#' Algorithms that find ranks of importance of discrete attributes, basing on their entropy with a continous class attribute. This function
#' is a reimplementation of \pkg{FSelector}'s \link[FSelector]{information.gain},
#' \link[FSelector]{gain.ratio} and \link[FSelector]{symmetrical.uncertainty}.
#'
#' @details
#'
#' \code{type = "infogain"} is \deqn{H(Class) + H(Attribute) - H(Class,
#' Attribute)}{H(Class) + H(Attribute) - H(Class, Attribute)}
#'
#' \code{type = "gainratio"} is \deqn{\frac{H(Class) + H(Attribute) - H(Class,
#' Attribute)}{H(Attribute)}}{(H(Class) + H(Attribute) - H(Class, Attribute)) /
#' H(Attribute)}
#'
#' \code{type = "symuncert"} is \deqn{2\frac{H(Class) + H(Attribute) - H(Class,
#' Attribute)}{H(Attribute) + H(Class)}}{2 * (H(Class) + H(Attribute) - H(Class,
#' Attribute)) / (H(Attribute) + H(Class))}
#'
#' where H(X) is Shannon's Entropy for a variable X and H(X, Y) is a joint
#' Shannon's Entropy for a variable X with a condition to Y.
#'
#' @param formula An object of class \link{formula} with model description.
#' @param data A \link{data.frame} accompanying formula.
#' @param x A \link{data.frame} or sparse matrix with attributes.
#' @param y A vector with response variable.
#' @param type Method name.
#' @param equal A logical. Whether to discretize dependent variable with the
#' \code{equal frequency binning discretization} or not.
#' @param nbins Number of bins used for discretization. Only used if `equal = TRUE` and the response is numeric.
#' @param discIntegers logical value.
#' If true (default), then integers are treated as numeric vectors and they are discretized.
#' If false  integers are treated as factors and they are left as is.
#' @param threads defunct. Number of threads for parallel backend - now turned off because of safety reasons.
#' @param confInt A number between 0 and 1 indicating the confidence interval or FALSE to turn them off.
#' default: 95% confidence interval
#' @param nBoot Number of draws to calculate confidence intervals. default: 1000
#'
#' @return
#'
#' data.frame with the following columns:
#' \itemize{
#'  \item{attributes}{ - variables names.}
#'  \item{importance}{ - worth of the attributes.}
#' }
#'
#' @author Zygmunt Zawadzki \email{zygmunt@zstat.pl}
#'
#' @examples
#'
#' irisX <- iris[-5]
#' y <- iris$Species
#'
#' ## data.frame interface
#' information_gain(x = irisX, y = y)
#'
#' # formula interface
#' information_gain(formula = Species ~ ., data = iris)
#' information_gain(formula = Species ~ ., data = iris, type = "gainratio")
#' information_gain(formula = Species ~ ., data = iris, type = "symuncert")
#'
#' # sparse matrix interface
#' library(Matrix)
#' i <- c(1, 3:8); j <- c(2, 9, 6:10); x <- 7 * (1:7)
#' x <- sparseMatrix(i, j, x = x)
#' y <- c(1, 1, 1, 1, 2, 2, 2, 2)
#'
#' information_gain(x = x, y = y)
#' information_gain(x = x, y = y, type = "gainratio")
#' information_gain(x = x, y = y, type = "symuncert")
#'
#' @importFrom Rcpp evalCpp
#' @importFrom stats na.omit
#' @importFrom stats complete.cases
#' @useDynLib FSelectorRcpp, .registration = TRUE
#' @rdname information_gain
#' @export
#'
information_gain <- function(formula, data, x, y,
                             type = c("infogain", "gainratio", "symuncert"),
                             equal = FALSE, discIntegers = TRUE, nbins = 5,
                             threads = 1, confInt = 0.95, nBoot = 1000) {

  if (!xor(
          all(!missing(x), !missing(y)),
          all(!missing(formula), !missing(data)))) {
    stop(paste("Please specify both `x = attributes, y = response`,",
               "XOR use both `formula = response ~ attributes, data = dataset"))
  }
  if (sum(!missing(x), !missing(y), !missing(formula), !missing(data)) > 2){
    stop(paste("Please specify both `x = attributes, y = response`,",
               "XOR use both `formula = response ~ attributes, data = dataset"))
  }

  if((!is.numeric(confInt) || confInt > 1 || confInt <= 0) && confInt){
    stop("confInt must be a number between 0 and 1 or FALSE")
  }

  if (!missing(x) && !missing(y)) {
    if (class(x) == "formula") {
      stop(paste("Please use `formula = response ~ attributes, data = dataset`",
                 "interface instead of `x = formula`."))
    }
    res <- .information_gain(x = x, y = y, type = type,
                             equal = equal, nbins = nbins, threads = threads,
                             discIntegers = discIntegers)
    if(confInt){
      res_matrix <- do.call('rbind', lapply(seq_len(nBoot), .boot, x = x, y = y,
                                            type = type, equal = equal,
                                            nbins = nbins, threads = threads,
                                            discIntegers = discIntegers))
      confint_lower <- (1 - confInt) / 2
      confint_res <- apply(res_matrix, 2, quantile, probs = c(confint_lower, 1 - confint_lower))
      res <- cbind(res, t(confint_res))
      colnames(res) = c("attributes", "importance", "lower", "upper")
    }
    return(res)
  }

  if (!missing(formula) && !missing(data)) {
    res <- .information_gain(formula, data, type, equal, nbins,
                             threads, discIntegers = discIntegers)
    if(confInt){
      res_matrix <- do.call('rbind', lapply(seq_len(nBoot), .boot, x = formula, y = data,
                                            type = type, equal = equal,
                                            nbins = nbins, threads = threads,
                                            discIntegers = discIntegers))
      confint_lower <- (1 - confInt) / 2
      confint_res <- apply(res_matrix, 2, quantile, probs = c(confint_lower, 1 - confint_lower))
      res <- cbind(res, t(confint_res))
      colnames(res) = c("attributes", "importance", "lower", "upper")
    }
    return(res)
  }
}

.information_gain <- function(x, y,
                              type = c("infogain", "gainratio", "symuncert"),
                              equal = FALSE,
                              nbins = 5,
                              discIntegers = TRUE,
                              threads = 1) {
  UseMethod(".information_gain", x)
}

.information_gain.default <- function(x, y,
                                      type = c("infogain",
                                               "gainratio",
                                               "symuncert"),
                                      equal = FALSE,
                                      discIntegers = TRUE,
                                      threads = 1) {
  stop("Unsupported data type.")
}

.information_gain.data.frame <- function(x, y,
                                         type = c("infogain",
                                                  "gainratio",
                                                  "symuncert"),
                                         equal = FALSE,
                                         discIntegers = TRUE,
                                         nbins = 5,
                                         threads = 1) {
  type <- match.arg(type)

  if (anyNA(y)) {
    warning(paste("There are missing values in the dependent variable",
                  "information_gain will remove them."))
    idx <- FSelectorRcpp:::complete.cases(y)
    x <- x[idx, , drop = FALSE] #nolint
    y <- y[idx]
  }

  if (is.double(y)) {

    if (!equal) {
      warning(paste("Dependent variable is a numeric! It will be converted",
                    "to factor with simple factor(y). We do not discretize",
                    "dependent variable in FSelectorRcpp by default! You can",
                    "choose equal frequency binning discretization by setting",
                    "equal argument to TRUE."))
    } else {
      y <- equal_freq_bin(y, nbins)
    }

  }

  if (!is.factor(y)) {
    y <- factor(y)
  }

  values <- FSelectorRcpp:::information_gain_cpp(x, y,
                threads = threads, discIntegers = discIntegers)
  classEntropy <- FSelectorRcpp:::fs_entropy1d(y)

  results <- FSelectorRcpp:::information_type(classEntropy, values, type)
  data.frame(
    attributes = colnames(x),
    importance = results, stringsAsFactors = FALSE)
}

.information_gain.formula <- function(x, y,
                                      type = c("infogain",
                                               "gainratio",
                                               "symuncert"),
                                      equal = FALSE,
                                      nbins = 5,
                                      discIntegers = TRUE,
                                      threads = 1) {
  if (!is.data.frame(y)) {
    stop("y must be a data.frame!")
  }

  formula <- x
  data <- y

  names_from_formula <- FSelectorRcpp:::formula2names(formula, data)

  x <- data[, names_from_formula$x, drop = FALSE]
  y <- unname(unlist(data[, names_from_formula$y]))

  type <- match.arg(type)

  .information_gain.data.frame(
    x = x, y = y, type = type, equal = equal, nbins = nbins,
    discIntegers = discIntegers,
    threads = threads)
}


.information_gain.dgCMatrix <- function(x, y,
                                        type = c("infogain",
                                                 "gainratio",
                                                 "symuncert"),
                                        equal = FALSE,
                                        nbins = 5,
                                        discIntegers = TRUE,
                                        threads = 1) {
  type <- match.arg(type)

  values <- FSelectorRcpp:::sparse_information_gain_cpp(x, y, discIntegers = discIntegers)
  classEntropy <- fs_entropy1d(y)

  results <- FSelectorRcpp:::information_type(classEntropy, values, type)

  attr <- colnames(x)
  if (is.null(attr)) {
    attr <- 1:ncol(x)
  }

  data.frame(attributes = attr, importance = results, stringsAsFactors = FALSE)
}

information_type <- function(classEntropy, values,
                             type = c("infogain", "gainratio", "symuncert")) {
  attrEntropy <- values$entropy
  jointEntropy <- values$joint

  results <- classEntropy + attrEntropy - jointEntropy

  if (type == "gainratio") {
    results <- results / attrEntropy
  } else if (type == "symuncert") {
    results <- 2 * results / (attrEntropy + classEntropy)
  }

  results
}

.boot <- function(n, x, y, type, equal, nbins, threads, discIntegers){

  if(is.data.frame(y)){
    y = y[sample(seq_len(nrow(y)), replace = TRUE), ]
  }else{
    indeces = sample(seq_along(y), replace = TRUE)
    y = y[indeces]
    x = x[indeces, ]
  }
  res <- .information_gain(x = x, y = y, type = type,
                    equal = equal, nbins = nbins, threads = threads,
                    discIntegers = discIntegers)
  res$importance
}


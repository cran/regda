rda.tune <- function(x, ina, nfolds = 10, gam = seq(0, 1, by = 0.1), del = seq(0, 1, by = 0.1),
                     ncores = 1, folds = NULL, stratified = TRUE, seed = NULL) {
  ## x contains the data
  ## gam is between pooled covariance and diagonal
  ## gam*Spooled+(1-gam)*diagonal
  ## del is between QDA and LDA
  ## del*QDa+(1-del)*LDA
  ## if ncores==1, then 1 processor is used, otherwise more are
  ## used (parallel computing)
  ## if a matrix with folds is supplied in mat the results will
  ## always be the same. Leave it NULL otherwise
  ina <- as.numeric(ina)
  n <- dim(x)[1]  ## total sample size
  nc <- max(ina) ## number of groups
  D <- dim(x)[2]  ## number of variables
  sk <- array( dim = c(D, D, nc) )
  lg <- length(gam)    ;    ld <- length(del)
  if ( is.null(folds) )  folds <- .makefolds(ina, nfolds = nfolds,
                                                           stratified = stratified, seed = seed)
  nfolds <- length(folds)

  if (ncores > 1) {
    runtime <- proc.time()
    group <- matrix(nrow = length(gam), ncol = length(del) )
    cl <- parallel::makePSOCKcluster(ncores)
    doParallel::registerDoParallel(cl)
    if ( is.null(folds) )  folds <- .makefolds(ina, nfolds = nfolds,
                                                             stratified = stratified, seed = seed)
    ww <- foreach(vim = 1:nfolds, .combine = cbind, .export = c("mahala", "rowMaxs", "colGroup", "cova"),
	      .packages = c("Rfast", "Rfast2") ) %dopar% {
      test <- x[ folds[[ vim ]], , drop = FALSE]  ## test sample
      id <- ina[ folds[[ vim ]] ] ## groups of test sample
      train <- x[ -folds[[ vim ]], , drop = FALSE]   ## training sample
      ida <- ina[ -folds[[ vim ]] ]  ## groups of training sample
      na <- tabulate(ida)
      ci <- 2 * log(na / sum(na) )
      mesi <- Rfast2::colGroup(train, as.integer(ida) ) / na
      na <- rep(na - 1, each = D^2)
      ## the covariance matrix of each group is now calculated
      for (m in 1:nc)  sk[ , , m] <- Rfast::cova( train[ida == m, ] )
      s <- na * sk
      Sp <- colSums( aperm(s) ) / (sum(na) - nc)  ## pooled covariance matrix
      sp <- diag( sum( diag( Sp ) ) / D, D )
      gr <- matrix(nrow = length( folds[[ vim ]] ), ncol = nc)

      for ( k1 in 1:length(gam) ) {
        Sa <- gam[k1] * Sp + (1 - gam[k1]) * sp  ## regularised covariance matrix
        for ( k2 in 1:length(del) ) {
          for (j in 1:nc) {
            Ska <- del[k2] * sk[, , j] + (1 - del[k2]) * Sa
            gr[, j] <- ci[j] - log( det( Ska ) ) - Rfast::mahala( test, mesi[j, ], Ska )
            ## the scores are doubled, for efficiency I did not multiply with 0.5
          }
          g <- Rfast::rowMaxs(gr)
          group[k1, k2] <- mean( g == id )
        }
      }
      return( as.vector( group ) )
    }
    parallel::stopCluster(cl)

    per <- array( dim = c( lg, ld, nfolds ) )
    for ( i in 1:nfolds )  per[, , i] <- matrix( ww[, i], nrow = lg )
    runtime <- proc.time() - runtime

  } else {
    runtime <- proc.time()
    per <- array( dim = c( lg, ld, nfolds ) )

    for (vim in 1:nfolds) {

      test <- x[ folds[[ vim ]], , drop = FALSE ]   ## test sample
      id <- ina[ folds[[ vim ]] ] ## groups of test sample
      train <- x[ -folds[[ vim ]], , drop = FALSE]  ## training sample
      ida <- ina[ -folds[[ vim ]] ]   ## groups of training sample
      na <- tabulate(ida)
      ci <- 2 * log(na / sum(na) )
      mesi <- Rfast2::colGroup(train, as.integer(ida) ) / na
      na <- rep(na - 1, each = D^2)
      ## the covariance matrix of each group is now calculated
      for (m in 1:nc)  sk[ , , m] <- Rfast::cova( train[ida == m, ] )
      s <- na * sk
      Sp <- colSums( aperm(s) ) / (sum(na) - nc)  ## pooled covariance matrix
      sp <- diag( sum( diag( Sp ) ) / D, D )
      gr <- matrix(nrow = length( folds[[ vim ]] ), ncol = nc)

      for ( k1 in 1:length(gam) ) {
        Sa <- gam[k1] * Sp + (1 - gam[k1]) * sp  ## regularised covariance matrix
        for ( k2 in 1:length(del) ) {
          for (j in 1:nc) {
            Ska <- del[k2] * sk[, , j] + (1 - del[k2]) * Sa
            gr[, j] <- ci[j] - log( det( Ska ) ) - Rfast::mahala( test, mesi[j, ], Ska )
            ## the scores are doubled, for efficiency I did not multiply with 0.5
          }
          g <- Rfast::rowMaxs(gr)
          per[k1, k2, vim] <- mean( g == id )
        }
      }

    }  ##  end  for (vim in 1:nfolds) {
    runtime <- proc.time() - runtime
  }

  percent <- t( colMeans( aperm(per) ) )
  su <- apply(per, 1:2, sd)
  dimnames(percent) <- dimnames(su) <- list(gamma = gam, delta = del)
  confa <- as.vector( which(percent == max( percent ), arr.ind = TRUE )[1, ] )
  result <- cbind( max(percent), gam[ confa[1] ], del[ confa[2] ] )
  colnames(result) <- c('optimal', 'best gamma', 'best delta')
  list(per = per, percent = percent, se = su, result = result, runtime = runtime)
}





.makefolds <- function(ina, nfolds = 10, stratified = TRUE, seed = NULL) {
  names <- paste("Fold", 1:nfolds)
  runs <- sapply(names, function(x) NULL)
  if ( !is.null(seed) )  set.seed(seed)

  if ( !stratified ) {
    rat <- length(ina) %% nfolds
    suppressWarnings({
      mat <- matrix( Rfast2::Sample.int( length(ina) ), ncol = nfolds )
    })
    mat[-c( 1:length(ina) )] <- NA
    for ( i in 1:c(nfolds - 1) )  runs[[ i ]] <- mat[, i]
    a <- prod(dim(mat)) - length(ina)
    runs[[ nfolds ]] <- mat[1:c(nrow(mat) - a), nfolds]
  } else {
    labs <- unique(ina)
    run <- list()
    for (i in 1:length(labs)) {
      names <- which( ina == labs[i] )
      run[[ i ]] <- sample(names)
    }
    run <- unlist(run)
    for ( i in 1:length(ina) ) {
      k <- i %% nfolds
      if ( k == 0 )  k <- nfolds
      runs[[ k ]] <- c( runs[[ k ]], run[i] )
    }
  }

  for (i in 1:nfolds)  {
    if ( any( is.na(runs[[ i ]]) ) )  runs[[ i ]] <- runs[[ i ]][ !is.na(runs[[ i ]]) ]
  }

  if ( length(runs[[ nfolds ]]) == 0 ) runs[[ nfolds ]] <- NULL
  runs
}




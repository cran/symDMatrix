symDMatrix
==========

[![CRAN_Status_Badge](http://www.r-pkg.org/badges/version/symDMatrix)](https://CRAN.R-project.org/package=symDMatrix)
[![Rdoc](http://www.rdocumentation.org/badges/version/symDMatrix)](http://www.rdocumentation.org/packages/symDMatrix)
[![Travis-CI Build Status](https://travis-ci.org/QuantGen/symDMatrix.svg?branch=master)](https://travis-ci.org/QuantGen/symDMatrix)
[![AppVeyor Build Status](https://ci.appveyor.com/api/projects/status/7cei04chrkvxke27?svg=true)](https://ci.appveyor.com/project/agrueneberg/symdmatrix)
[![Coverage status](https://codecov.io/gh/QuantGen/symDMatrix/branch/master/graph/badge.svg)](https://codecov.io/github/QuantGen/symDMatrix?branch=master)

symDMatrix is an R package that provides symmetric matrices partitioned into file-backed blocks.

A symmetric matrix `G` is partitioned into blocks as follows:

```
+ --- + --- + --- +
| G11 | G12 | G13 |
+ --- + --- + --- +
| G21 | G22 | G23 |
+ --- + --- + --- +
| G31 | G32 | G33 |
+ --- + --- + --- +
```

Because the matrix is assumed to be symmetric (i.e., `Gij` equals `Gji`), only the diagonal and upper-triangular blocks are stored and the other blocks are virtual transposes of the corresponding diagonal blocks. Each block is a file-backed matrix of type `ff_matrix` of the [ff](https://CRAN.R-project.org/package=ff) package.

The package defines the class and multiple methods that allow treating this file-backed matrix as a standard RAM matrix.


Tutorial
--------

### (0) Creating a symmetric matrix in RAM

Before we start, let's create a symmetric matrix in RAM.

```R
library(BGLR)

# Load genotypes from a mice data set
data(mice)
X <- mice.X
rownames(X) <- paste0("ID_", 1:nrow(X))

# Compute a symmetric genetic relationship matrix (G matrix) in RAM
G1 <- tcrossprod(scale(X))
G1 <- G1 / mean(diag(G1))
```

### (1) Converting a RAM matrix into a symDMatrix

In practice, if we can hold a matrix in RAM, there is not much of a point to convert it to a `symDMatrix` object; however, this will help us to get started.

```R
library(symDMatrix)

G2 <- as.symDMatrix(G1, blockSize = 400, vmode = "double", folderOut = "mice")
```

### (2) Exploring operators

Now that we have a `symDMatrix` object, let's illustrate some operators.

```R
# Basic operators applied to a matrix in RAM and to a symDMatrix

# Dimension operators
all.equal(dim(G1), dim(G2))
nrow(G1) == nrow(G2)
ncol(G1) == ncol(G2)
all.equal(diag(G1), diag(G2))

# Names operators
all.equal(dimnames(G1), dimnames(G2))
all(rownames(G1) == rownames(G2))
all(colnames(G1) == rownames(G2))

# Block operators
nBlocks(G2)
blockSize(G2)

# Indexing (can use booleans, integers or labels)
G2[1:2, 1:2]
G2[c("ID_1", "ID_2"), c("ID_1", "ID_2")]
tmp <- c(TRUE, TRUE, rep(FALSE, nrow(G2) - 2))
G2[tmp, tmp]
head(G2[tmp, ])

# Exhaustive check of indexing
for (i in 1:100) {
    n1 <- sample(1:50, size = 1)
    n2 <- sample(1:50, size = 1)
    i1 <- sample(1:nrow(X), size = n1)
    i2 <- sample(1:nrow(X), size = n2)
    TMP1 <- G1[i1, i2, drop = FALSE]
    TMP2 <- G2[i1, i2, drop = FALSE]
    stopifnot(all.equal(TMP1, TMP2))
}
```

### (3) Creating a symDMatrix from genotypes

The function `getG_symDMatrix` of the [BGData](https://CRAN.R-project.org/package=BGData) package computes G=XX' (with options for centering and scaling) without ever loading G in RAM. It creates the `symDMatrix` object directly, block by block. In this example, `X` is a matrix in RAM. For large genotype data sets, `X` could be a file-backed matrix, e.g., a `BEDMatrix` or `ff` object.

```R
library(BGData)

G3 <- getG_symDMatrix(X, blockSize = 400, vmode = "double", folderOut = "mice2")
class(G3)
all.equal(diag(G1), diag(G3))

for(i in 1:10){
    n1 <- sample(1:25, size = 1)
    i1 <- sample(1:25, size = n1)
    for(j in 1:10){
        n2 <- sample(1:nrow(G1), size = 1)
        i2 <- sample(1:nrow(G1), size = n2)
        tmp1 <- G1[i1, i2]
        tmp2 <- G3[i1, i2]
        stopifnot(all.equal(tmp1, tmp2))
    }
}
```

### (4) Creating a symDMatrix from `ff` files containing the blocks

The function `symDMatrix` allows creating a `symDMatrix` object from a list of `.RData` files containing `ff_matrix` objects. The list is assumed to provide, in order, files for `G11, G12, ..., G1q, G22, G23, ..., G2q, ..., Gqq`. This approach is useful for very large G matrices. If `n` is large it may make sense to compute the blocks of the `symDMatrix` object in parallel jobs (e.g., in an HPC). The function `getG` of the [BGData](https://CRAN.R-project.org/package=BGData) package is similar to `getG_symDMatrix` but accepts arguments `i1` and `i2` which define a block of G (i.e., rows of `X`).

```R
library(BGLR)
library(BGData)
library(ff)

# Load genotypes from a wheat data set
data(wheat)
X <- wheat.X
rownames(X) <- paste0("ID_", 1:nrow(X))

# Compute G matrix in RAM
centers <- colMeans(X)
scales <- apply(X = X, MARGIN = 2, FUN = sd)
G1 <- tcrossprod(scale(X, center = centers, scale = scales))
G1 <- G1 / mean(diag(G1))

# Compute G matrix block by block (each block computation can be distributed)
nBlocks <- 3
blockSize <- ceiling(nrow(X) / nBlocks)
i <- 1:nrow(X)
blockIndices <- split(i, ceiling(i / blockSize))
for (r in 1:nBlocks) {
    for (s in r:nBlocks) {
        blockName <- paste0("wheat_", r, "_", s - r + 1)
        block <- getG(X, center = centers, scale = scales, scaleG = TRUE,
                      i = blockIndices[[r]], i2 = blockIndices[[s]])
        block <- ff::as.ff(block, filename = paste0(blockName, ".bin"), vmode = "double")
        save(block, file = paste0(blockName, ".RData"))
    }
}
G2 <- as.symDMatrix(list.files(pattern = "^wheat.*RData$"))
attr(G2, "centers") <- centers
attr(G2, "scales") <- scales

all.equal(diag(G1), diag(G2)) # there will be a slight numerical penalty
```


Installation
------------

Install the stable version from CRAN:

```R
install.packages("symDMatrix")
```

Alternatively, install the development version from GitHub:

```R
# install.packages("remotes")
remotes::install_github("QuantGen/symDMatrix")
```


Documentation
-------------

Further documentation can be found on [RDocumentation](http://www.rdocumentation.org/packages/symDMatrix).


Contributing
------------

- Issue Tracker: https://github.com/QuantGen/symDMatrix/issues
- Source Code: https://github.com/QuantGen/symDMatrix

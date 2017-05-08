#' A Class to Represent a Symmetric Matrix Paritioned into Memory-Mapped
#' Blocks.
#'
#' A `symDMatrix` is a symmetric matrix partitioned into matrix-like (ideally
#' memory-mapped) blocks. This approach allows for very large symmetric
#' matrices, commonly found for example when computing genetic relationship
#' matrices on large cohorts. A `symDMatrix` object behaves similarly to a
#' regular `matrix` by implementing key methods such as `[`, `dim`, and
#' `dimnames`.
#'
#' Each block is a matrix-like block. Currently supported are `ff` objects.
#' Because the matrix is symmetric, only the diagonal and upper-triangular
#' blocks are stored.
#'
#' @slot data A nested list in the form of \code{[[G11, G12, G13, ..., G1q],
#' [G22, G23, ..., G2q], [...], [Gqq]]}, each list element representing a block
#' of a partitioned symmetric and upper-triangular matrix. There are `(q * (q +
#' 1)) / 2` blocks in total and each list level consists of `q - i` blocks,
#' where `q` is the number of column/row blocks and `i` is the current row
#' index. All blocks except the ones in the last column/row are expected to
#' have the same dimensions.
#' @slot centers A numeric vector storing the values used for column centering
#' when creating the symmetric matrix.
#' @slot scales A numeric vector storing the values used for column scaling
#' when creating the symmetric matrix.
#' @example man/examples/symDMatrix.R
#' @seealso [initialize()][initialize,symDMatrix-method()] to create a
#' `symDMatrix` object from scratch, [as.symDMatrix()] to create a `symDMatrix`
#' object from other objects.
#' @aliases symDMatrix-class
#' @export symDMatrix
#' @exportClass symDMatrix
symDMatrix <- setClass("symDMatrix", slots = c(data = "list", centers = "numeric", scales = "numeric"))


#' Create a New symDMatrix Instance.
#'
#' This method is run when a [symDMatrix-class] object is created using
#' `symDMatrix(...)` or `new("symDMatrix", ...)`.
#'
#' Several structural checks are performed on `data`: it must contain at least
#' one block and have the following nested structure: \code{[[G11, G12, G13,
#' ..., G1q], [G22, G23, ..., G2q], [...], [Gqq]]}. Each block must be
#' matrix-like and have the same number of rows or columns as blocks in the
#' same row or column, respectively. Non-final blocks have to be square, unless
#' if there is only a single block, in which case that block also has to be
#' square.
#'
#' @param .Object The [symDMatrix-class] instance to be initialized. This
#' argument is passed in by R and can be ignored, but still needs to be
#' documented.
#' @param data A nested list of blocks.
#' @param centers A numeric vector storing the values used for column centering
#' when creating the symmetric matrix.
#' @param scales A numeric vector storing the values used for column scaling
#' when creating the symmetric matrix.
#' @return A [symDMatrix-class] object.
#' @example man/examples/initialize.R
#' @seealso [as.symDMatrix()] to create a [symDMatrix-class] object from other
#' objects.
#' @export
setMethod("initialize", "symDMatrix", function(.Object, data, centers = 0L, scales = 1L) {
    nBlocks <- length(data)
    # Test that there is at least one block
    if (nBlocks == 0L) {
        stop("data needs to contain at least one block")
    }
    # Test that data has the right structure
    blocksPerRow <- sapply(data, length)
    if (!identical(blocksPerRow, seq(nBlocks, 1L))) {
        stop("data needs to be a nested list in the following structure: [[G11, G12, G13, ..., G1q], [G22, G23, ..., G2q], [...], [Gqq]]")
    }
    # Block-level tests
    rowDims <- rep(NA_integer_, nBlocks)
    colDims <- rep(NA_integer_, nBlocks)
    for (i in seq(0L, nBlocks - 1L)) {
        for (j in seq(1L, nBlocks - i)) {
            block <- data[[i + 1L]][[j]]
            # Test that all blocks are matrix-like
            if (!isMatrixLike(block)) {
                stop("data: all blocks need to be matrix-like objects")
            }
            # Test that all blocks per row have the same number of rows
            if (is.na(rowDims[i + 1L])) {
                rowDims[i + 1L] <- nrow(block)
            } else {
                if (nrow(block) != rowDims[i + 1L]) {
                    stop("data: all blocks per row need the same number of rows")
                }
            }
            # Test that all blocks per column have the same number of columns
            if (is.na(colDims[j + i])) {
                colDims[j + i] <- ncol(block)
            } else {
                if (ncol(block) != colDims[j + i]) {
                    stop("data: all blocks per column need the same number of columns")
                }
            }
        }
    }
    if (nBlocks > 1L) {
        # Test that non-final blocks are square
        if (any(rowDims[-length(rowDims)] != colDims[-length(colDims)])) {
            stop("data: non-final blocks need to be square")
        }
    } else {
        # Test that the first block is square
        if (nrow(data[[1]][[1]]) != ncol(data[[1]][[1]])) {
            stop("data: the first block needs to be square")
        }
    }
    .Object@data <- data
    .Object@centers <- centers
    .Object@scales <- scales
    return(.Object)
})


#' @export
is.matrix.symDMatrix <- function(x) {
    TRUE
}


#' @export
dim.symDMatrix <- function(x) {
    p <- sum(sapply(x@data[[1L]], ncol))
    c(p, p)
}


#' @export
length.symDMatrix <- function(x) {
    prod(dim(x))
}


names.symDMatrix <- function(x) {
    blockNames <- lapply(x@data[[1L]], function(block) {
        colnames(block)
    })
    isNULL <- sapply(blockNames, function(blockName) {
        is.null(blockName)
    })
    if (any(isNULL)) {
        NULL
    } else {
        unlist(blockNames)
    }
}


#' @export
dimnames.symDMatrix <- function(x) {
    names <- names.symDMatrix(x)
    if (is.null(names)) {
        NULL
    } else {
        list(names, names)
    }
}


#' @export
`[.symDMatrix` <- function(x, i, j, drop = TRUE) {

    nargs <- nargs()

    nX <- nrow(x)

    # Single Index: x[i]
    if (nargs == 2L && !missing(i) && missing(j)) {

        singleIndex <- TRUE

        n <- 1L
        p <- length(i)

        # Convert single index to multi index
        k <- i - 1L
        paired_i <- k %% nX
        paired_j <- as.integer(k / nX)
        paired_i <- paired_i + 1L
        paired_j <- paired_j + 1L

    # No index and multi Index: x[], or x[, ], and x[i, j], x[i, ], or x[, j]
    } else {

        singleIndex <- FALSE

        pX <- ncol(x)

        if (missing(i)) {
            i <- 1L:nX
        } else if (typeof(i) == "logical") {
            i <- rep_len(i, nX)
            i <- which(i)
        } else if (typeof(i) == "character") {
            i <- match(i, rownames(x))
        } else if (typeof(i) == "double") {
            i <- as.integer(i)
        }
        if (missing(j)) {
            j <- 1L:pX
        } else if (typeof(j) == "logical") {
            j <- rep_len(j, pX)
            j <- which(j)
        } else if (typeof(j) == "character") {
            j <- match(j, colnames(x))
        } else if (typeof(j) == "double") {
            j <- as.integer(j)
        }

        n <- length(i)
        p <- length(j)

        # Create all combinations of i and j
        paired_i <- rep(i, each = p)
        paired_j <- rep(j, times = n)

    }

    # Switch indices for combinations in which i is larger than j to redirect
    # queries to the lower triangle to the upper triangle
    switch <- paired_i > paired_j
    flip <- paired_i[switch]
    paired_i[switch] <- paired_j[switch]
    paired_j[switch] <- flip

    # Retrieve block size
    blockSize <- blockSize(x)

    # Create retrieval index
    row_blocks <- as.integer(ceiling(paired_i / blockSize))
    col_blocks <- as.integer(ceiling(paired_j / blockSize))
    local_i <- paired_i - (row_blocks - 1L) * blockSize
    local_j <- paired_j - (col_blocks - 1L) * blockSize

    # Initialize output matrix
    names <- names.symDMatrix(x)
    if (!is.null(names) && !singleIndex) {
        dimnames <- list(names[i], names[j])
    } else {
        dimnames <- NULL
    }
    OUT <- matrix(data = double(), nrow = n, ncol = p, dimnames = dimnames)

    # Create output index
    out_i <- rep(1L:n, each = p)
    out_j <- rep(1L:p, times = n)

    # Retrieve elements by block
    for (row_block in unique(row_blocks)) {
        row_block_matches <- row_blocks == row_block
        for (col_block in unique(col_blocks[row_block_matches])) {
            cur_block <- row_block_matches & col_blocks == col_block
            block <- x@data[[row_block]][[col_block - row_block + 1L]]
            out_idx <- (out_j[cur_block] - 1L) * n + out_i[cur_block]
            local_idx <- (local_j[cur_block] - 1L) * nrow(block) + local_i[cur_block]
            OUT[out_idx] <- block[local_idx]
        }
    }

    if (drop == TRUE && (n == 1L || p == 1L)) {
        return(OUT[, ])
    } else {
        return(OUT)
    }

}


#' Load symDMatrix Objects from .RData Files.
#'
#' This function is similar to [base::load()], but also initializes the
#' different matrix-like objects that [symDMatrix-class] can take. Currently
#' supported are `ff_matrix` objects.
#'
#' @param file The name of an .RData file to be loaded.
#' @param envir The environment where to load the data.
#' @export
load.symDMatrix <- function(file, envir = parent.frame()) {
    # Load data into new environment
    loadingEnv <- new.env()
    load(file = file, envir = loadingEnv)
    names <- ls(envir = loadingEnv)
    for (name in names) {
        object <- get(name, envir = loadingEnv)
        # Initialize blocks of symDMatrix objects
        if (class(object) == "symDMatrix") {
            nBlocks <- nBlocks(object)
            for (i in 1L:nBlocks) {
                for (j in i:nBlocks) {
                    object@data[[i]][[j - i + 1L]] <- initializeBlock(object@data[[i]][[j - i + 1L]], path = dirname(file))
                }
            }
        }
        # Assign object to envir
        assign(name, object, envir = envir)
    }
    message("Loaded objects: ", paste0(names, collapse = ", "))
}


initializeBlock <- function(x, ...) {
    UseMethod("initializeBlock")
}


# Absolute paths to ff files are not stored, so the ff objects have to be
# loaded from the same directory as the RData file.
initializeBlock.ff_matrix <- function(x, path, ...) {
    if (!requireNamespace("ff", quietly = TRUE)) {
        stop("The ff package is needed for this function to work. Please install it.", call. = FALSE)
    }
    # Store current working directory and set working directory to path
    cwd <- getwd()
    setwd(path)
    # Open ff object
    ff::open.ff(x)
    # Restore the working directory
    setwd(cwd)
    return(x)
}


initializeBlock.default <- function(x, ...) {
    return(x)
}


#' Return the Number of Column/Row Blocks of a symDMatrix Object.
#'
#' This function returns the number of row blocks the original matrix has been partitioned into.
#'
#' @param x A [symDMatrix-class] object.
#' @return The number of column/row blocks of a [symDMatrix-class] object.
#' @example man/examples/nBlocks.R
#' @export
nBlocks <- function(x) {
    length(x@data[[1L]])
}


#' Return the Block Size of a symDMatrix Object.
#'
#' This function returns the block size of a [symDMatrix-class] object.
#'
#' The last block of a column/row may be smaller than the other blocks. Its
#' size can be retrieved by setting `last` to `TRUE`.
#'
#' @param x A [symDMatrix-class] object.
#' @param last A boolean indicating whether to return the block size of the
#' last (`TRUE`) column/row block or any of the other blocks (`FALSE`,
#' default).
#' @return The block size of a [symDMatrix-class] object.
#' @example man/examples/blockSize.R
#' @export
blockSize <- function(x, last = FALSE) {
    row <- x@data[[1L]]
    if (last) {
        ncol(row[[length(row)]])
    } else {
        ncol(row[[1L]])
    }
}


#' Return the Block Structure of a symDMatrix Object.
#'
#' This function returns the block structure of a [symDMatrix-class] object and
#' can be useful when implementing custom indexing techniques.
#'
#' @param x A [symDMatrix-class] object.
#' @return A matrix with three columns: the block number, the start index and
#' the end index.
#' @export
blockIndex <- function(x) {
    n <- length(x@data)
    index <- matrix(nrow = n, ncol = 3L)
    colnames(index) <- c("block", "ini", "end")
    end <- 0L
    for (i in 1L:n) {
        ini <- end + 1L
        end <- ini + nrow(x@data[[i]][[1L]]) - 1L
        index[i, ] <- c(i, ini, end)
    }
    return(index)
}


#' Coerce an Object to a symDMatrix Object.
#'
#' Coerce an object to a [symDMatrix-class] object.
#'
#' @param x A numeric matrix.
#' @param ... Additional arguments.
#' @return A [symDMatrix-class] object.
#' @seealso [as.symDMatrix.matrix()] to coerce a matrix or
#' [as.symDMatrix.character()] to coerce a vector of path names to a
#' [symDMatrix-class] object.
#' @export
as.symDMatrix <- function(x, ...) {
    UseMethod("as.symDMatrix")
}


#' Coerce a Matrix to a symDMatrix Object.
#'
#' This function creates a [symDMatrix-class] from a numeric matrix that is
#' assumed to be symmetric.
#'
#' The input matrix is broken into blocks and each block is stored as an `ff`
#' object. In addition, a metadata object called `symDMatrix.RData` is created
#' to allow for easy reloading of the [symDMatrix-class] object.
#'
#' @param x A symmetric numeric matrix.
#' @param blockSize The number of rows and columns of each block. If `NULL`, a
#' single block of the same dimensions as `x` will be created. Defaults to
#' 5000.
#' @param vmode The vmode used to store the data in the `ff` objects.
#' @param folderOut A name for a folder where to store the data of the
#' resulting [symDMatrix-class] object.
#' @param ... Additional arguments (currently unused).
#' @return A [symDMatrix-class] object.
#' @seealso [load.symDMatrix()] to reload the [symDMatrix-class] object.
#' @export
as.symDMatrix.matrix <- function(x, blockSize = 5000L, vmode = "double", folderOut = randomString(), ...) {

    if (!requireNamespace("ff", quietly = TRUE)) {
        stop("The ff package is needed for this function to work. Please install it.", call. = FALSE)
    }

    n <- nrow(x)

    if (ncol(x) != n) {
        stop("x must be a square matrix")
    }

    if (file.exists(folderOut)) {
        stop(folderOut, " already exists")
    }
    dir.create(folderOut)

    # Determine number of blocks from block size
    nBlocks <- as.integer(ceiling(nrow(x) / blockSize))

    # Determine subjects of each block
    index <- matrix(data = integer(), nrow = nBlocks, ncol = 3L)
    index[1L, ] <- c(1L, 1L, min(n, blockSize))
    if (nBlocks > 1L) {
        for (i in 2L:nBlocks) {
            index[i, 1L] <- i
            index[i, 2L] <- index[(i - 1L), 3L] + 1L
            index[i, 3L] <- min(index[i, 2L] + blockSize - 1L, n)
        }
    }

    # Create nested list
    dataList <- vector(mode = "list", length = nBlocks)
    for (r in 1L:nBlocks) {
        rowIndex <- seq(index[r, 2L], index[r, 3L])
        dataList[[r]] <- vector(mode = "list", length = nBlocks - r)
        for (s in r:nBlocks) {
            colIndex <- seq(index[s, 2L], index[s, 3L])
            blockName <- paste0("data_", padDigits(r, nBlocks), "_", padDigits(s, nBlocks), ".bin")
            block <- ff::ff(dim = c(length(rowIndex), length(colIndex)), vmode = vmode, initdata = x[rowIndex, colIndex], filename = paste0(folderOut, "/", blockName))
            colnames(block) <- colnames(x)[colIndex]
            rownames(block) <- rownames(x)[rowIndex]
            # Change ff path to a relative one
            bit::physical(block)$filename <- blockName
            dataList[[r]][[s - r + 1L]] <- block
        }
    }

    # Create symDMatrix object from nested list
    symDMatrix <- symDMatrix(data = dataList, centers = 0L, scales = 1L)

    # Save RData object
    save(symDMatrix, file = "symDMatrix.RData")

    return(symDMatrix)
}


#' Coerce a Character Vector to a symDMatrix Object.
#'
#' This function creates a [symDMatrix-class] object from a character vector of
#' path names to `RData` files, each containing exactly one matrix-like object
#' that is used as a block, and is useful for distributed computing where each
#' block is processed on a different node.
#'
#' The `RData` files must be ordered by block: `G11, G12, G13, ..., G1q, G22,
#' G23, ..., G2q, ..., Gqq`. The matrix-like objects are initialized similarly
#' to [load.symDMatrix()].
#'
#' @param x A character vector with path names to `RData` files.
#' @param centers A numeric vector to fill the `@@centers` slot of the
#' [symDMatrix-class] object.
#' @param scales A numeric vector to fill the `@@scales` slot of the
#' [symDMatrix-class] object.
#' @param ... Additional arguments (currently unused).
#' @return A [symDMatrix-class] object.
#' @seealso [base::list.files()] to create a character vector of file paths
#' that match a certain pattern.
#' @export
as.symDMatrix.character <- function(x, centers = 0L, scales = 1L, ...) {
    nBlocks <- as.integer((-1L + sqrt(1L + 4L * 2L * length(x))) / 2L)
    dataList <- vector(mode = "list", length = nBlocks)
    counter <- 1L
    for (i in 1L:nBlocks) {
        dataList[[i]] <- vector(mode = "list", length = nBlocks - i)
        for (j in i:nBlocks) {
            loadingEnv <- new.env()
            file <- x[[counter]]
            load(file = file, envir = loadingEnv)
            names <- ls(envir = loadingEnv)
            # Make sure that at least and at most one object is matrix-like
            isMatrixLike <- sapply(names, function(name) {
                object <- get(name, envir = loadingEnv)
                isMatrixLike(object)
            })
            if (sum(isMatrixLike) != 1L) {
                stop("only one object per RData file can be a matrix-like object")
            }
            object <- get(names[which(isMatrixLike)], envir = loadingEnv)
            # Initialize the matrix-like object
            object <- initializeBlock(object, path = dirname(file))
            dataList[[i]][[j - i + 1L]] <- object
            counter <- counter + 1L
        }
    }
    G <- symDMatrix(data = dataList, centers = centers, scales = scales)
    return(G)
}


randomString <- function(n = 10L) {
    paste(sample(c(0L:9L, letters, LETTERS), size = n, replace = TRUE), collapse = "")
}


padDigits <- function(x, total) {
    formatC(x, width = as.integer(log10(total) + 1L), format = "d", flag = "0")
}


isMatrixLike <- function(x) {
    length(dim(x)) == 2L
}
\name{blockSize}
\alias{blockSize}
\title{Return the Block Size of a symDMatrix Object}
\description{
    This function returns the block size of a \code{symDMatrix} object.
}
\usage{
blockSize(x, last = FALSE)
}
\arguments{
    \item{x}{
        A \code{symDMatrix} object.
    }
    \item{last}{
        A boolean indicating whether to return the block size of the last
        (\code{TRUE}) column/row block or any of the other blocks
        (\code{FALSE}, default).
    }
}
\details{
    The last block of a column/row may be smaller than the other blocks. Its
    size can be retrieved by setting \code{last} to \code{TRUE}.
}
\value{
    The block size of a \code{symDMatrix} object.
}
\examples{
# Load example symDMatrix (G)
load.symDMatrix(system.file("extdata", "G.RData", package = "symDMatrix"), readonly = TRUE)

# Get the block size
blockSize(G)

# Get the block size of the trailing blocks
blockSize(G, last = TRUE)
}

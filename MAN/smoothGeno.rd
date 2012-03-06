\name{smoothGeno}
\alias{smoothGeno}


\title{Smooth genotype.}

\description{
 Remove genotyping errors by smoothing.
}

\usage{
	smoothGeno(cross,windowSize=1,chr,population,map=c("genetic","physical"),verbose=FALSE)
}

\arguments{
\item{cross}{ An object of class \code{cross}. See \code{\link[qtl]{read.cross}} for details. }
 \item{windowSize}{ Specifies number of markers that are processed at once.}
 \item{chr}{ Specifies subset of chromosomes to be processed.}
 \item{population}{ An object of class \code{\link{population}}. See \code{\link{createPopulation}} for details. }
 \item{map}{ Which map (from ones stored in population$maps) should be used fo assigning chromosomes on the created map}
  \item{verbose}{ Be verbose.}
}

\value{
  An object of class \code{cross}. See \code{\link[qtl]{read.cross}} for details. 
}

\details{
This function is usefull while creating new map (also a bit while saturating existing map). It is taking a number of markers at the time (specified by user) and checking values 
of markers bordering those selected. If border values at both sides are the same and they are different from value of selected markers, then selected markers are given value of
border ones. Then the windows slides by one marker and another group is checked.

If there are some markers on the map that shall be treated special (this will be a case while smoothing a cross containing a saturated map and one doesn't want to modify original markers), an object of class population shall be provided. Original markers from population$offspring$genotypes$real are matched with ones in the cross object by names. They are not modified and their position is obtained from the map specified by user.
}

\author{
	Konrad Zych \email{konrad.zych@uj.edu.pl}, Danny Arends \email{Danny.Arends@gmail.com}
	Maintainer: Konrad Zych \email{konrad.zych@uj.edu.pl}
}

\examples{
	data(yeastCross)
  yeastCross_smooth <- smoothGeno(yeastCross,3)
  geno.image(yeastCross)
	geno.image(yeastCross_smooth)
  
}

\seealso{
  \itemize{
    \item{\code{\link{cross.denovo}}}{ -  Creating de novo genetic map or chromosome assignment vector.}
    \item{\code{\link{cross.saturate}}}{ - Saturate existing map.}
  }
}

\keyword{manip}

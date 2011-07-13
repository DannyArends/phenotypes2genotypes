############################################################################################################
#
# postprocessing.R
#
# Copyright (c) 2011, Konrad Zych
#
# Modified by Danny Arends
# 
# first written March 2011
# last modified July 2011
# last modified in version: 0.8.1 
# in current version: active, in main workflow
#
#     This program is free software; you can redistribute it and/or
#     modify it under the terms of the GNU General Public License,
#     version 3, as published by the Free Software Foundation.
#
#     This program is distributed in the hope that it will be useful
#     but without any warranty; without even the implied warranty of
#     merchantability or fitness for a particular purpose.  See the GNU
#     General Public License, version 3, for more details.
#
#     A copy of the GNU General Public License, version 3, is available
#     at http://www.r-project.org/Licenses/GPL-3
#
# Contains: orderChromosomes, majorityRule.internal, mergeChromosomes.internal, cleanMap
#			switchChromosomes.internal, removeChromosomes.internal, removeChromosomesSub.internal,
#
############################################################################################################

############################################################################################################
#									*** postProc ***
#
# DESCRIPTION:
# 	post processing obtained cross object to achieve best genetic map
# 
# PARAMETERS:
# 	cross - object of class cross, containing physical or genetic map
# 	n.linkGroups - expected number of linkage groups
# 	max.rf.range - range, within which max.rf parameter of formLinkageGroup will be checked
# 	min.lod.range - range, within which min.lod parameter of formLinkageGroup will be checked
#	verbose - be verbose
#
# OUTPUT:
#	matrix conatining 8 cols:
#		#1 max.rf used in analysis
#		#2 min.lod used in analysis
#		#3 number of linkage groups obtained using values 1 and 2 by formLinkageGroups
#		#4 number of linkage groups left after removing groups with less then 0.5% of all markers (or less
#			than 3 markers if 0.5% of all of them is less than 3
#		#5 percentage of markers in groups from point 4
#		#6 number of linkage groups left after removing groups with number higher than n.linkGroups (so 
#			exactly n.linkGroups or less
#		#7 percentage of markers in groups from point 6
#		#8 score obtained by scoreResults.internal (the higher, the better match we have)
#
############################################################################################################
postProc <- function(cross,n.linkGroups,max.rf.range=c(0.15,0.30),min.lod.range=c(0,3),verbose=FALSE){
	filename <- "postProctemp.tmp"
	if(missing(n.linkGroups)) stop("n.linkGroups in an obligatory parameter")
	cross <- est.rf(cross)
	crossLength <- sum(nmar(cross))
	minDist <- round(crossLength*0.05)
	if(minDist<3) minDist <- 3
	cat("",file=filename)
	if(length(max.rf.range)==2) max.rf.range[3] <- 0.01
	if(length(min.lod.range)==2) min.lod.range[3] <- 1
	if(length(max.rf.range)!=3) stop("max.rf.range should be provided with 2 or 3 arguments, see ?postProc\n")
	if(length(min.lod.range)!=3) stop("min.lod.range should be provided with 2 or 3 arguments ?postProc\n")
	if(any(!(is.numeric(max.rf.range)))) stop("max.rf.range should contain only numerics\n")
	if(any(!(is.numeric(min.lod.range)))) stop("max.rf.range should contain only numerics\n")
	cur.rf <- max.rf.range[1]
	while(cur.rf<=max.rf.range[2]){
		cur.lod <- min.lod.range[1]
		while(cur.lod<=min.lod.range[2]){
			cross_ <- formLinkageGroups(cross, max.rf=cur.rf, min.lod=cur.lod, reorgMarkers=TRUE, verbose=verbose)
			cat(cur.rf,cur.lod,length(cross_$geno),file=filename,sep="\t",append=TRUE)
			cat("\t",file=filename,append=TRUE)
			cross__ <- removeTooSmallChromosomes(cross_,minNrOfMarkers=minDist,verbose=verbose)
			cat(length(cross__$geno),(sum(nmar(cross__))/crossLength),file=filename,sep="\t",append=TRUE)
			cat("\t",file=filename,append=TRUE)
			cross__ <- reduceChromosomesNumber(cross_,numberOfChromosomes=n.linkGroups,verbose=verbose)
			cat(length(cross__$geno),(sum(nmar(cross__))/crossLength),file=filename,sep="\t",append=TRUE)
			cat("\n",file=filename,append=TRUE)
			cross_ <- NULL
			cross__ <- NULL
			doCleanUp.internal()
			cur.lod <- cur.lod + min.lod.range[3]
		}
		cur.rf <- cur.rf + max.rf.range[3]
	}
	results <- as.matrix(read.table(filename,sep="\t"))
	results <- cbind(results,apply(results,1,scoreResults.internal,n.linkGroups))
	invisible(results)
}

############################################################################################################
#									*** scoreResults.internal ***
#
# DESCRIPTION:
# 	simple scoring of results obtained by postProc
# 
# PARAMETERS:
# 	resultRow - row of matrix obtained using postProc
# 	n.linkGroups - expected number of linkage groups
#
# OUTPUT:
#	integer
#
############################################################################################################
scoreResults.internal <- function(resultRow,n.linkGroups){
	score <- 0
	score <- score + abs(resultRow[3]-n.linkGroups)*(-100)
	score <- score + abs(resultRow[4]-n.linkGroups)*(-100)
	score <- score + abs(resultRow[6]-n.linkGroups)*(-100)
	score <- score + resultRow[5]*100 + resultRow[7]*100
	invisible(score)
}

fLG.internal <- function(cross,max.rf,min.lod){
	additions <- getAdditionsOfCross.internal(cross)
	cross <- formLinkageGroups(cross, reorgMarkers=TRUE,max.rf=max.rf,min.lod=min.lod)
	cross <- putAdditionsOfCross.internal(cross, additions)
	invisible(cross)
}

getAdditionsOfCross.internal <-function(cross){
	additions <- NULL
	if(!(is.null(cross$maps$physical))){
		additions$map_p <- cross$maps$physical 
	}
	if(!(is.null(cross$maps$genetic))){
		additions$map_g <-cross$maps$genetic
	}
	if(!(is.null(cross$genotypes$real))){
		additions$geno <- cross$genotypes$real 
	}
	invisible(additions)
}

putAdditionsOfCross.internal <-function(cross,additions){
	if(!is.null(additions$map_p)) cross$maps$physical <- additions$map_p
	if(!is.null(additions$map_g)) cross$maps$genetic <- additions$map_g
	if(!is.null(additions$geno)) cross$genotypes$real <- additions$geno
	invisible(cross)
}

############################################################################################################
#									*** orderChromosomes ***
#
# DESCRIPTION:
# 	ordering chromosomes using physical map and majority rule
# 
# PARAMETERS:
# 	cross - object of class cross, containing physical or genetic map
# 	map - which map should be used for comparison:
#			- genetic - genetic map from cross$maps$genetic
#			- physical - physical map from cross$maps$physical
#	verbose - be verbose
#
# OUTPUT:
#	object of class cross
#
############################################################################################################
orderChromosomes <- function(cross,method=c("majority","corelation"),map=c("genetic","physical"),verbose=FALSE){
	additions <- getAdditionsOfCross.internal(cross)
	defaultCheck.internal(method, "method", 2)
	defaultCheck.internal(map, "map", 2)
	inListCheck.internal(map,"map",c("genetic","physical"))
	inListCheck.internal(method,"method",c("majority","corelation"))
	crossContainsMap.internal(cross,map)
	if(map=="genetic"){
		cur_map <- cross$maps$genetic
	}else if(map=="physical"){
		cur_map <- cross$maps$physical
	}
	if(method=="majority"){
		cross <- orderChromosomesMR.internal(cross, cur_map, verbose)
	}else{
		cross <- orderChromosomesC.internal(cross, cur_map, verbose)
	}
	cross <- putAdditionsOfCross.internal(cross, additions)
	invisible(cross)
}

############################################################################################################
#									*** orderChromosomesC.internal ***
#
# DESCRIPTION:
# 	simpel scoring of results obtained by postProc
# 
# PARAMETERS:
# 	resultRow - row of matrix obtained using postProc
# 	n.linkGroups - expected number of linkage groups
#
# OUTPUT:
#	integer
#
############################################################################################################
orderChromosomesC.internal <- function(cross,cur_map,verbose=FALSE){
	output <- bestCorelated.internal(cross,cur_map)
	### until every chr on phys map is match exactly once
	while(max(apply(output,2,sum))>1){
		toMerge <- which(apply(output,2,sum)>1)
		for(curToMerge in toMerge){
			curMerge <- which(output[,curToMerge]==max(output[,curToMerge]))
			cross <- mergeChromosomes.internal(cross,curMerge,curMerge[1])
			output <- bestCorelated.internal(cross,cur_map)
		}
	}
	if(verbose) cat(output,"\n")
	order1 <- matrix(0,ncol(output),nrow(output))
	order2 <- matrix(1,ncol(output),nrow(output))
	### until next iteration doesn't change the result
	while(any(order1!=order2)){
		order1 <- output
		for(l in 1:ncol(output)){
			cur <- which(output[,l]==max(output[,l]))
			if(cur!=l)cross <- switchChromosomes.internal(cross,cur,l)
			output <-bestCorelated.internal(cross,cur_map)
		}
		order2 <- output
	}
	names(cross$geno) <- 1:length(cross$geno)
	invisible(cross)
}

############################################################################################################
#									*** bestCorelated.internal ***
#
# DESCRIPTION:
# 	subfunction of segragateChromosomes.internal, returns matrix showing for every reco map chromosome from 
#	which physicall map chromosome majority of markers comes
# 
# PARAMETERS:
# 	cross - object of class cross, containing physical or genetic map
#	map - which map should be used for comparison:
#			- genetic - genetic map from cross$maps$genetic
#			- physical - physical map from cross$maps$physical
# 
# OUTPUT:
#	vector with new ordering of chromosomes inside cross object
#
############################################################################################################
bestCorelated.internal <- function(cross,cur_map){
	knchrom <- length(table(cur_map[,1]))
	result <- matrix(0, length(cross$geno), knchrom)
	output <- matrix(0, length(cross$geno), knchrom)
	for(i in 1:length(cross$geno)){
		cur_ys <- cross$geno[[i]]$data[c(-25,-39,-99),]
		for(j in 1:knchrom){
			cur_xs <- t(cross$genotypes$real[rownames(cur_map)[which(cur_map[,1]==j)],c(-70,-74)])
			result[i,j] <- mean(cor(cbind(cur_ys,cur_xs),use="pairwise.complete.obs"))
		}
		output[i,which(result[i,]==max(result[i,]))] <- 1
	}
	rownames(result) <- 1:nrow(result)
	colnames(result) <- 1:ncol(result)
	rownames(output) <- 1:nrow(output)
	colnames(output) <- 1:ncol(output)
	
	if(min(apply(output,2,max))!=1){
		toCheck <- which(apply(output,2,sum)!=1)
		for(x in toCheck){
			output[,x] <- 0
			output[which(result[,x]==max(result[,x])),x] <- 1
		}
	}	
	print(output)
	invisible(output)
}

############################################################################################################
#									*** orderChromosomesMR.internal ***
#
# DESCRIPTION:
# 	ordering chromosomes using physical map and majority rule
# 
# PARAMETERS:
# 	cross - object of class cross, containing physical or genetic map
# 	map - which map should be used for comparison:
#			- genetic - genetic map from cross$maps$genetic
#			- physical - physical map from cross$maps$physical
#	verbose - be verbose
#
# OUTPUT:
#	object of class cross
#
############################################################################################################
orderChromosomesMR.internal <- function(cross,cur_map,verbose=FALSE){
	output <- majorityRule.internal(cross,cur_map)
	### until every chr on phys map is match exactly once
	while(max(apply(output,2,sum))>1){
		toMerge <- which(apply(output,2,sum)>1)
		for(curToMerge in toMerge){
			curMerge <- which(output[,curToMerge]==max(output[,curToMerge]))
			cross <- mergeChromosomes.internal(cross,curMerge,curMerge[1])
			output <- majorityRule.internal(cross,cur_map)
		}
	}
	if(verbose) cat(output,"\n")
	order1 <- matrix(0,ncol(output),nrow(output))
	order2 <- matrix(1,ncol(output),nrow(output))
	### until next iteration doesn't change the result
	while(any(order1!=order2)){
		order1 <- output
		for(l in 1:ncol(output)){
			cur <- which(output[,l]==max(output[,l]))
			if(cur!=l)cross <- switchChromosomes.internal(cross,cur,l)
			output <- majorityRule.internal(cross,cur_map)
		}
		order2 <- output
	}
	names(cross$geno) <- 1:length(cross$geno)
	invisible(cross)
}

############################################################################################################
#									*** majorityRule.internal ***
#
# DESCRIPTION:
# 	subfunction of segragateChromosomes.internal, returns matrix showing for every reco map chromosome from 
#	which physicall map chromosome majority of markers comes
# 
# PARAMETERS:
# 	cross - object of class cross, containing physical or genetic map
#	map - which map should be used for comparison:
#			- genetic - genetic map from cross$maps$genetic
#			- physical - physical map from cross$maps$physical
# 
# OUTPUT:
#	vector with new ordering of chromosomes inside cross object
#
############################################################################################################
majorityRule.internal <- function(cross,cur_map){
	knchrom <- length(table(cur_map[,1]))
	result <- matrix(0, length(cross$geno), knchrom)
	output <- matrix(0, length(cross$geno), knchrom)
	for(i in 1:length(cross$geno)){
		cur_ys <- colnames(cross$geno[[i]]$data)
		cur_xs <- cur_map[cur_ys,]
		for(j in 1:knchrom){
			result[i,j] <- sum(cur_xs[,1]==j)/nrow(cur_xs)
		}
		output[i,which(result[i,]==max(result[i,]))] <- 1
	}
	rownames(result) <- 1:nrow(result)
	colnames(result) <- 1:ncol(result)
	rownames(output) <- 1:nrow(output)
	colnames(output) <- 1:ncol(output)
	
	if(min(apply(output,2,max))!=1){
		toCheck <- which(apply(output,2,sum)!=1)
		for(x in toCheck){
			output[,x] <- 0
			output[which(result[,x]==max(result[,x])),x] <- 1
		}
	}	
	invisible(output)
}

############################################################################################################
#									*** mergeChromosomes.internal ***
#
# DESCRIPTION:
#	subfunction of segragateChromosomes.internal, merging multiple chromosomes into one
# 
# PARAMETERS:
# 	cross - object of class cross
# 	chromosomes - chromosomes to be merged
# 	name - name of merged chromosome
# 
# OUTPUT:
#	object of class cross
#
############################################################################################################
mergeChromosomes.internal <- function(cross, chromosomes, name, verbose=FALSE){
	if(verbose)cat("Merging chromosomes",chromosomes,"to form chromosome",name,"names:",names(cross$geno),"\n")
	geno <- cross$geno
	markerNames <- NULL
	for(j in chromosomes){
		if(j!=name) markerNames <- c(markerNames, colnames(geno[[j]]$data))
	}
	for(k in markerNames) cross <- movemarker(cross, k, name)
	invisible(cross)
}

############################################################################################################
#									*** switchChromosomes.internal ***
#
# DESCRIPTION:
#	switching two chromosomes of cross object
# 
# cross - object of R/qtl cross type
# chr1, chr2 - numbers of chromosomes to be switched (1,2) == (2,1)
#
############################################################################################################
switchChromosomes.internal <- function(cross, chr1, chr2){
	cat(chr1,chr2,"\n")
	if(chr1!=chr2){
		geno <- cross$geno
		cross$geno[[chr1]] <- geno[[chr2]] 
		cross$geno[[chr2]] <- geno[[chr1]]
		cross <- est.rf(cross)
	}
	invisible(cross)
}


############################################################################################################
#									*** reduceChromosomesNumber ***
#
# DESCRIPTION:
#	Function to remove chromosomes from cross object. Those can specified in three ways described below.
# 
# PARAMETERS:
# 	cross - object of class cross
# 	numberOfChromosomes - how many chromosomes should stay (remove all but 1:numberOfChromosomes)
#	verbose - be verbose
# 
# OUTPUT:
#	object of class cross
#
############################################################################################################
reduceChromosomesNumber <- function(cross, numberOfChromosomes,verbose=FALSE){
	if(is.null(cross)&&!(any(class(cross)=="cross"))) stop("Not a cross object!\n")
	if(!(missing(numberOfChromosomes))){
		if(numberOfChromosomes<length(cross$geno)){
			for(i in length(cross$geno):(numberOfChromosomes+1)){
				cross <- removeChromosomesSub.internal(cross,i,verbose)
			}
		}
	}else{
		stop("You have to provide one of following: numberOfChromosomes, chromosomes or minLength")
	}
	invisible(cross)
}

############################################################################################################
#									*** removeChromosomes ***
#
# DESCRIPTION:
#	Function to remove chromosomes from cross object. Those can specified in three ways described below.
# 
# PARAMETERS:
# 	numberOfChromosomes - how many chromosomes should stay (remove all but 1:numberOfChromosomes)
# 	chromosomesToBeRmv - explicitly provide functions with NAMES of chromosomes to be removed
#	verbose - be verbose
# 
# OUTPUT:
#	object of class cross
#
############################################################################################################
removeChromosomes <- function(cross, chromosomesToBeRmv, verbose=FALSE){
	if(is.null(cross)&&!(any(class(cross)=="cross"))) stop("Not a cross object!\n")
	if(!(missing(chromosomesToBeRmv))){
		for(i in chromosomesToBeRmv){
			if(!(i%in%names(cross$geno))){
				stop("There is no chromosome called ",i,"\n")
			}else{
				cross <- removeChromosomesSub.internal(cross,i,verbose)
			}
		}
	}else{
		stop("You have to provide one of following: numberOfChromosomes, chromosomes or minLength")
	}
	invisible(cross)
}

############################################################################################################
#									*** removeTooSmallChromosomes ***
#
# DESCRIPTION:
#	Function to remove chromosomes from cross object. Those can specified in three ways described below.
# 
# PARAMETERS:
# 	cross - object of class cross
#	verbose - be verbose
# 	minNrOfMarkers - specify minimal number of markers chromosome is allowed to have (remove all that have
#					 less markers than that)
# 
# OUTPUT:
#	object of class cross
#
############################################################################################################
removeTooSmallChromosomes <- function(cross, minNrOfMarkers, verbose=FALSE){
	if(is.null(cross)&&!(any(class(cross)=="cross"))) stop("Not a cross object!\n")
	if(!(missing(minNrOfMarkers))){
		if(length(cross$geno)>1){
			if(length(cross$geno[[1]]$map)<minNrOfMarkers) minNrOfMarkers <- length(cross$geno[[1]]$map)-1
			for(i in length(cross$geno):1){
				if(length(cross$geno[[i]]$map)<minNrOfMarkers){
					cross <- removeChromosomesSub.internal(cross,i,verbose)
				}
			}
		}
	}else{
		stop("You have to provide one of following: numberOfChromosomes, chromosomes or minLength")
	}
	invisible(cross)
}

############################################################################################################
#									*** removeChromosomesSub.internal ***
#
# DESCRIPTION:
#	subfunction of removeChromosomes.internal, removing from given cross object specified chromosome
# 
# PARAMETERS:
# 	cross - object of class cross
# 	chr - chromosome to be removed (number or name)
# 
# OUTPUT:
#	object of class cross
#
############################################################################################################
removeChromosomesSub.internal <- function(cross, chr,verbose=FALSE){
	additions <- getAdditionsOfCross.internal(cross)
	if(verbose)cat("removing chromosome:",chr," markers:",names(cross$geno[[chr]]$map),"\n")
	cross$rmv <- cbind(cross$rmv,cross$geno[[chr]]$data)
	cross <- drop.markers(cross, names(cross$geno[[chr]]$map))
	cross <- putAdditionsOfCross.internal(cross, additions)
	invisible(cross)
}

############################################################################################################
#										*** cleanMap ***
#
# DESCRIPTION:
#	removes markers that cause the recombination map to expand more than a given percentage (of its total
#	length)
# 
# PARAMETERS:
# 	cross - R/qtl cross type object
# 	difPercentage - If by removing a marker the map gets shorter by this percentage (or more). The marker 
#		will be dropped.
#	minChrLenght - chromosomes shorter than that won't be processed
# 	verbose - Be verbose
# 	debugMode - 1: Print our checks, 2: print additional time information 
# 
# OUTPUT:
#	object of class cross
#
############################################################################################################
cleanMap <- function(cross, difPercentage, minChrLenght,verbose=FALSE, debugMode=0){
	if(verbose && debugMode==1) cat("cleanMap starting withour errors in checkpoint.\n")
	s <- proc.time()
	for(i in 1:length(cross$geno)){
		begMarkers <- length(cross$geno[[i]]$map)
		begLength <- max(cross$geno[[i]]$map)
		for(j in names(cross$geno[[i]]$map)){
			if(max(cross$geno[[i]]$map)>minChrLenght){
				cur_max <- max(cross$geno[[i]]$map)
				cross2 <- drop.markers(cross,j)
				newmap <- est.map(cross2,offset=0)
				cross2 <- replace.map(cross2, newmap)
				new_max <- max(cross2$geno[[i]]$map)
				dif <- cur_max-new_max
				if(dif > (difPercentage/100 * cur_max)){
					if(verbose) cat("------Removed marker:",j,"to make chromosome",i,"map smaller from",cur_max,"to",new_max,"\n")
					cross <- cross2
				}
			}
		}
		removed <- begMarkers-length(cross$geno[[i]]$map)
		if(removed>0)cat("Removed",removed,"out of",begMarkers,"markers on chromosome",i," which led to shortening map from ",begLength,"to",max(cross$geno[[i]]$map),"(",100*(begLength-max(cross$geno[[i]]$map))/begLength,"%)\n")
	}
	e <- proc.time()
	if(verbose && debugMode==2)cat("Map cleaning done in:",(e-s)[3],"seconds.\n")
	invisible(cross)
}
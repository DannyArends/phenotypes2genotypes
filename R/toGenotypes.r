############################################################################################################
#
# toGenotypes.R
#
# Copyright (c) 2011, Konrad Zych
#
# Modified by Danny Arends
# 
# first written March 2011
# last modified April 2011
# last modified in version: 0.4.4
# in current version: active, in main workflow
#
#     This program is free software; you can redistribute it and/or
#     modify it under the terms of the GNU General Public License,
#     version 3, as published by the Free Software Foundation.
#
#     This program is distributed in the hope that it will be useful,
#     but without any warranty; without even the implied warranty of
#     merchantability or fitness for a particular purpose.  See the GNU
#     General Public License, version 3, for more details.
#
#     A copy of the GNU General Public License, version 3, is available
#     at http://www.r-project.org/Licenses/GPL-3
#
# Contains: toGenotypes
#           convertToGenotypes.internal, splitRow.internal, filterGenotypes.internal, filterRow.internal
#			sortMap.internal, majorityRule.internal, mergeChromosomes.internal
#
############################################################################################################

############################################################################################################
#toGenotypes: Function that chooses from the matrix only appropriate markers with specified rules
# 
# ril - Ril type object, must contain parental phenotypic data.
# use - Which genotypic matrix should be saved to file, real - supported by user and read from file, 
#	simulated - made by toGenotypes, ap - simulated data orderd using gff map
# treshold - If Rank Product pval for gene is lower that this value, we assume it is being diff. expressed.
# overlapInd - Number of individuals that are allowed in the overlap
# proportion - Proportion of individuals expected to carrying a certain genotype 
# margin - Proportion is allowed to varry between this margin (2 sided)
# minChrLength -if maximal distance between the markers in the chromosome is lower than this value,
#	whole chromosome will be dropped
# ... - Parameters passed to formLinkageGroups.
# verbose - Be verbose
# debugMode - 1: Print our checks, 2: print additional time information
#
############################################################################################################
toGenotypes <- function(ril, use=c("real","simulated","map"), treshold=0.01, overlapInd = 0, proportion = c(50,50), margin = 15, minChrLength = 0, verbose=FALSE, debugMode=0,...){
	#*******CHECKS*******
	require(qtl)
	if(proportion < 1 || proportion > 99) stop("Proportion is a percentage (1,99)")
	#if(overlapInd < 0 || overlapInd > ncol(expressionMatrix)) stop("overlapInd is a number (0,lenght of the row).")
	if(margin < 0 || margin > proportion) stop("Margin is a percentage (0,proportion)")
	if(verbose && debugMode==1) cat("toGenotypes starting withour errors in checkpoint.\n")
	
	#*******CONVERTING CHILDREN PHENOTYPIC DATA TO GENOTYPES*******
	s1 <- proc.time()
	ril <- convertToGenotypes.internal(ril, treshold, overlapInd, proportion, margin, verbose, debugMode)
	e1 <- proc.time()
	if(verbose && debugMode==2)cat("Converting phenotypes to genotypes done in:",(e1-s1)[3],"seconds.\n")
	
	
	#*******SAVING CROSS OBJECT*******
	s1 <- proc.time()
	cross <- genotypesToCross.internal(ril,use=use,verbose=verbose,debugMode=debugMode)
	e1 <- proc.time()
	if(verbose && debugMode==2)cat("Creating cross object done in:",(e1-s1)[3],"seconds.\n")
	
	#*******ENHANCING CROSS OBJECT*******
	if(use!="map"){
		### FormLinkage groups
		cross <- invisible(formLinkageGroups(cross,reorgMarkers=TRUE,verbose=verbose,...))
		
		### remove shitty chromosomes
		cross <- removeChromosomes.internal(cross,minChrLength)
		### saving as separated object, beacause orderMarkers will remove it from cross object
		removed <- cross$rmv
		
		### Order markers
		cross <- orderMarkers(cross, use.ripple=TRUE, verbose=verbose)
		
		### Adding real maps		
		if(!(is.null(ril$rils$map))){
			ril <- sortMap.internal(ril)
			cross$maps$physical <- ril$rils$map
		}
		
		### Majority rule used to order linkage groups
		cross <- segregateChromosomes.internal(cross)
		
		### adding info about removed markers
		cross$rmv <- removed
	}
	
	#*******RETURNING CROSS OBJECT*******
	invisible(cross)
}

############################################################################################################
#convertToGenotypes.internal: function splitting differentially expressed markers into two genotypes
# 
# ril - Ril type object, must contain parental phenotypic data.
# treshold - If Rank Product pval for gene is lower that this value, we assume it is being diff. expressed.
# overlapInd - Number of individuals that are allowed in the overlap
# proportion - Proportion of individuals expected to carrying a certain genotype 
# margin - Proportion is allowed to varry between this margin (2 sided)
# verbose - Be verbose
# debugMode - 1: Print our checks, 2: print additional time information 
#
############################################################################################################
convertToGenotypes.internal <- function(ril, treshold, overlapInd, proportion, margin, verbose=FALSE, debugMode=0){
	if(verbose && debugMode==1) cat("convertToGenotypes starting.\n")
	if(length(proportion)==2){
		genotypesUp <- c(0,1)
		genotypesDown <- c(1,0)
	}else if(length(proportion)==3){
		genotypesUp <- c(0,1,2)
		genotypesDown <- c(2,1,0)
	}
	output <- NULL
	markerNames <- NULL 
	upParental <- ril$parental$phenotypes[which(ril$parental$RP$pval[1] < treshold),]
	downParental <- ril$parental$phenotypes[which(ril$parental$RP$pval[2] < treshold),]
	upRils <- ril$rils$phenotypes[which(rownames(ril$rils$phenotypes) %in% rownames(upParental)),]
	downRils <- ril$rils$phenotypes[which(rownames(ril$rils$phenotypes) %in% rownames(downParental)),]

	for(x in rownames(upRils)){
		cur <- splitRow.internal(x, upRils, upParental, overlapInd, proportion, margin, ril$parental$groups, 1)
		if(!(is.null(cur))){
			output <- rbind(output,cur)
			markerNames <- c(markerNames,x)
		}
	}
	for(x in rownames(downRils)){
		cur <- splitRow.internal(x, downRils, downParental, overlapInd, proportion, margin, ril$parental$groups, 0)
		if(!(is.null(cur))){
			output <- rbind(output,cur)
			markerNames <- c(markerNames,x)
		}
	}
	ril$rils$genotypes$simulated <- output
	colnames(ril$rils$genotypes$simulated) <- colnames(upRils)
	rownames(ril$rils$genotypes$simulated) <- markerNames
	invisible(ril)
}

############################################################################################################
#splitRow.internal: subfunction of convertToGenotypes.internal, splitting one row
# 
# x - name of currently processed row
# rils - matrix of up/down regulated genes in rils
# parental - matrix of up/down regulated genes in parents
# overlapInd - Number of individuals that are allowed in the overlap
# proportion - Proportion of individuals expected to carrying a certain genotype 
# margin - Proportion is allowed to varry between this margin (2 sided)
# groupLabels - Specify which column of parental data belongs to group 0 and which to group 1.
# up - 1 - genes up 0 - down regulated
#
############################################################################################################
splitRow.internal <- function(x, rils, parental, overlapInd, proportion, margin, groupLabels, up=1){
	result <- rep(0,length(rils[x,]))
	A <- parental[which(rownames(parental) == x),which(groupLabels==0)]
	B <- parental[which(rownames(parental) == x),which(groupLabels==1)]
	splitVal <- mean(mean(A,na.rm=TRUE),mean(B,na.rm=TRUE))
	rils[x,which(is.na(rils[x,]))] <- splitVal
	a <- rils[x,] > splitVal
	b <- rils[x,] < splitVal
	if(length(proportion)==2){
		if(up==1){
			genotypes <- c(0,1)
		}else if(up==0){
			genotypes <- c(1,0)
		}
		result[which(a)] <- genotypes[1]
		result[which(b)] <- genotypes[2]
		result[which(rils[x,] == splitVal)] <- NA
		result <- filterRow.internal(result, overlapInd, proportion, margin, genotypes)
	}else if(length(proportion)==3){
		if(up==1){
			genotypes <- c(0,1,2)
		}else if(up==0){
			genotypes <- c(2,1,0)
		}
		subSplitValDown <- mean(rils[which(b),])
		subSplitValUp <- splitVal + (splitVal - mean(b))
		result[which(rils[x,] < subSplitValDown )] <- genotypes[1]
		result[which(rils[x,] > subSplitValUp )] <- genotypes[3]
		result[which((rils[x,] > subSplitValDown )&&(rils[x,] < subSplitValUp ))] <- genotypes[2]
		result[which(rils[x,] == splitVal)] <- NA
		result <- filterRow.internal(result, overlapInd, proportion, margin, genotypes)
	}
	invisible(result)
}

############################################################################################################
#filterRow.internal : removing from genotypic matrix genes that are no passing specified requirments
# 
# ril - Ril type object, must contain parental phenotypic data.
# overlapInd - Number of individuals that are allowed in the overlap
# proportion - Proportion of individuals expected to carrying a certain genotype 
# margin - Proportion is allowed to varry between this margin (2 sided)
# verbose - Be verbose
# debugMode - 1: Print our checks, 2: print additional time information

############################################################################################################
filterRow.internal <- function(result, overlapInd, proportion, margin, genotypes){
	if(length(proportion)==2){
		genotypes2 <- genotypes[c(2,1)]
	}else if(length(proportion)==3){
		genotypes2 <- genotypes[c(3,2,1)]
	}
	if(filterRowSub.internal(result,overlapInd,proportion, margin, genotypes)){
		invisible(result)
	}else if(filterRowSub.internal(result,overlapInd,proportion, margin, genotypes)){
		invisible(result)
	}else{
		return(NULL)
	}
}

############################################################################################################
#filterRowSub.internal : subfunction of filterGenotypes.internal, filtering one row
# 
# genotypeRow - currently processed row
# overlapInd - Number of individuals that are allowed in the overlap
# proportion - Proportion of individuals expected to carrying a certain genotype 
# margin - Proportion is allowed to varry between this margin (2 sided)
#
############################################################################################################
filterRowSub.internal <- function(result, overlapInd, proportion, margin, genotypes){
	for(i in 1:length(proportion)){
		cur <- sum(result==genotypes[i])/length(result) * 100
		if(is.na(cur)) return(FALSE)
		upLimit <- proportion[i] + margin/2
		downLimit <- proportion[i] - margin/2
		#cat(result,"\n",cur,upLimit,downLimit,"\n")
		if(!((cur < upLimit)&&(cur > downLimit))){
			return(FALSE)
		}
	}
	return(TRUE)
}

############################################################################################################
#sortMap.internal: subfunction of filterGenotypes.internal, filtering one row
# 
# ril - Ril type object
#
############################################################################################################
sortMap.internal <- function(ril){
	genes <- ril$rils$map
	result <- NULL
	nchr <- length(table(genes[,1]))
	lengths <- vector(mode="numeric",length=nchr+1)
	lengths[1] <- 0
	for(i in 1:nchr){
		current <- genes[which(genes[,1]==i),]
		lengths[i+1] <- max(current[,2]) + lengths[i] + 20000
		current <- current[names(sort(current[,2])),]
		current[,2] <- current[,2] + lengths[i]
		result <- rbind(result,current)
	}
	ril$rils$map <- list(result,lengths[-length(lengths)])
	invisible(ril)
}

############################################################################################################
#segragateChromosomes.internal  - ordering chromosomes using physical map
# 
# cross - object of R/qtl cross type
#
############################################################################################################
segregateChromosomes.internal <- function(cross){
	if(is.null(cross$maps$physical)){
		cat("WARNING: no physical map, function will return unchanged cross object\n")
	}else{
		output <- majorityRule.internal(cross)
		print(output)
		### until every chr on phys map is match exactly once
		while(max(apply(output,2,sum))>1){
			toMerge <- which(apply(output,2,sum)>1)
			for(curToMerge in toMerge){
				curMerge <- which(output[,curToMerge]==max(output[,curToMerge]))
				map <- cross$maps$physical
				cross <- mergeChromosomes.internal(cross,curMerge,curMerge[1])
				cross$maps$physical <- map
			}
			output <- majorityRule.internal(cross)
		}
		
		order1 <- matrix(0,ncol(output),nrow(output))
		order2 <- matrix(1,ncol(output),nrow(output))
		### until next iteration doesn't change the result
		while(any(order1!=order2)){
			order1 <- output
			for(l in 1:ncol(output)){
				cur <- which(output[,l]==max(output[,l]))
				if(cur!=l)cross <- switchChromosomes.internal(cross,cur,l)
				output <- majorityRule.internal(cross)
			}
			order2 <- output
		}
		names(cross$geno) <- 1:length(cross$geno)
	}
	invisible(cross)
}

############################################################################################################
#majorityRule.internal - subfunction of segragateChromosomes.internal, returns matrix showing for every
# reco map chromosome from which physicall map chromosome majority of markers comes
# 
# cross - object of R/qtl cross type
#
############################################################################################################
majorityRule.internal <- function(cross){
	knchrom <- length(table(cross$maps$physical[[1]][,1]))
	result <- matrix(0, length(cross$geno), knchrom)
	output <- matrix(0, length(cross$geno), knchrom)
	for(i in 1:length(cross$geno)){
		cur_ys <- colnames(cross$geno[[i]]$data)
		cur_xs <- cross$maps$physical[[1]][cur_ys,]
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
#mergeChromosomes.internal - subfunction of segragateChromosomes.internal, merging multiple chromosomes into
# one
# 
# cross - object of R/qtl cross type
# chromosomes - chromosomes to be merged
# name - chromosome
#
############################################################################################################
mergeChromosomes.internal <- function(cross, chromosomes, name){
	cat("Merging chromosomes",chromosomes,"to form chromosome",name,"\n")
	geno <- cross$geno
	names(geno)
	markerNames <- NULL
	for(j in chromosomes){
		if(j!=name) markerNames <- c(markerNames, colnames(geno[[j]]$data))
	}
	for(k in markerNames) cross <- movemarker(cross, k, name)
	cat("Ordering markers on newly merged chromosome\n")
	#cross <- orderMarkers(cross, chr=name)
	invisible(cross)
}



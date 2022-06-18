#!/bin/bash

cell_line=ENCSR880CUB
data_type="DNASE_SE"

date=$(date +'%m.%d.%Y')
bias_threshold_factor=0.9
setting=$data_type"_"$date"_"$bias_threshold_factor
cur_file_name="ENCSR880CUB_fold_0.sh"
setting=DNASE_SE_03.14.2022_0.9


### SIGNAL INPUT


in_bigwig=$PWD/"results/chrombpnet/DNASE_SE/ENCSR880CUB/data/ENCSR880CUB.bigWig"
overlap_peak=$PWD/"results/chrombpnet/DNASE_SE/ENCSR880CUB/data/peaks.bed.gz"
neg_data=$PWD/"results/chrombpnet/DNASE_SE/ENCSR880CUB/data/negatives_with_summit.bed"

#chrom_sizes=/mnt/data/annotations/by_release/hg38/hg38.chrom.sizes
#ref_fasta=/mnt/data/GRCh38_no_alt_analysis_set_GCA_000001405.15.fasta
#fold=/oak/stanford/groups/akundaje/projects/chrombpnet/model_inputs/ENCODE_ATAC_downloads/splits/fold_0.json
blacklist_region=$PWD/reference/GRch38_unified_blacklist.bed.gz
chrom_sizes=$PWD/reference/chrom.sizes
ref_fasta=$PWD/reference/hg38.genome.fa
fold=$PWD/splits/fold_0.json

oak_dir=/oak/stanford/groups/akundaje/projects/chrombpnet_paper_new/$data_type/$cell_line/
main_dir=$PWD/results/chrombpnet/$data_type/$cell_line
output_dir=$main_dir/$setting

inputlen=2114
gpu=0

function timestamp {
    # Function to get the current time with the new line character
    # removed 
    
    # current time
    date +"%Y-%m-%d_%H-%M-%S" | tr -d '\n'
}


## CREATE DIRS
if [[ -d $main_dir ]] ; then
    echo "main director already exists"
else
    mkdir $main_dir
fi

if [[ -d $output_dir ]] ; then
    echo "output director already exists"
else
    mkdir $output_dir
fi



### STEP 1 - TRAIN BIAS MODEL
if [[ -d $output_dir/bias_model ]] ; then
    echo "skipping bias model training  - directory present "
else
    mkdir $output_dir/bias_model
    CUDA_VISIBLE_DEVICES=$gpu bash step4_train_bias_model.sh $ref_fasta $in_bigwig $overlap_peak $neg_data $fold $bias_threshold_factor $output_dir/bias_model 
fi


### INTERPRET BIAS MODEL


if [[ -d $output_dir/bias_model/interpret ]] ; then
    echo "skipping bias model interpretation - directory present "
else
    mkdir $output_dir/bias_model/interpret

    logfile=$output_dir/bias_model/interpret/interpret.log
    touch $logfile

    echo $( timestamp ):"python $PWD/src/evaluation/interpret/interpret.py \
        --genome=$ref_fasta \
        --regions=results/chrombpnet/DNASE_SE/ENCSR880CUB/data/ENCSR880CUB.interpreted_regions.bed \
        --output_prefix=$output_dir/bias_model/interpret/$cell_line \
        --model_h5=$output_dir/bias_model/bias.h5" |  tee -a $logfile

    CUDA_VISIBLE_DEVICES=$gpu python $PWD/src/evaluation/interpret/interpret.py \
        --genome=$ref_fasta \
        --regions=results/chrombpnet/DNASE_SE/ENCSR880CUB/data/ENCSR880CUB.interpreted_regions.bed \
        --output_prefix=$output_dir/bias_model/interpret/$cell_line \
        --model_h5=$output_dir/bias_model/bias.h5  | tee -a $logfile
fi

if [[ -d $oak_dir/$setting/ ]]; then
    echo "dir exists"
else
    mkdir $oak_dir/$setting/
    mkdir $oak_dir/
    mkdir $oak_dir/$setting/BIAS
fi

if [[ -f $oak_dir/$setting/BIAS/$cell_line.counts_scores.h5  && -f $oak_dir/$setting/BIAS/$cell_line.profile_scores.h5 ]] ; then
    echo "bias model files already present on oak"
else
    echo "copying bias model counts and profile scores to oak"
    cp $output_dir/bias_model/interpret/$cell_line.counts_scores.h5 $oak_dir/$setting/BIAS/
    cp $output_dir/bias_model/interpret/$cell_line.profile_scores.h5 $oak_dir/$setting/BIAS/
fi


#!/bin/bash

# exit when any command fails
set -e

# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG

cleanup() {
    exit_code=$?
    if [ ${exit_code} == 0 ]
    then
	echo "Completed execution"
    else
	echo "\"${last_command}\" failed with exit code ${exit_code}."
    fi
}

# echo an error message before exiting
trap 'cleanup' EXIT INT TERM

# input files

while getopts i:d:g:c:p:n:f:b:o:s:h? flag

do
        case "${flag}" in
                i) in_bam=${OPTARG}
                        ;;
                d) data_type=${OPTARG}
                         ;;
                g) reference_fasta=${OPTARG}
                         ;;
                c) chrom_sizes=${OPTARG}
                         ;;
                p) peaks=${OPTARG}
                         ;;
                n) nonpeaks=${OPTARG}
                         ;;
                f) fold=${OPTARG}
                         ;;
                b) bias_model=${OPTARG}
                         ;;
                o) output_dir=${OPTARG}
                         ;;
                s) seed=${OPTARG}
                         ;;
                h) echo "script usage: $0 [-i input_bam] [-d ATAC_or_DNASE] [-g genome_fasta] [-c chrom_sizes] [-p peaks_bed] [-n nonpeaks_bed] [-f folds_json] [-b bias_model_h5] [-o output_dir_path]"
                         exit
                         ;;
                ?) echo "script usage: $0 [-i input_bam] [-d ATAC_or_DNASE] [-g genome_fasta] [-c chrom_sizes] [-p peaks_bed] [-n nonpeaks_bed] [-f folds_json] [-b bias_model_h5] [-o output_dir_path]" 
                         exit
                         ;;
                *) echo "Invalid option: -$flag"
                         exit 1 
                         ;;

        esac
done

in_bam=${in_bam?param missing -  bam file path missing}
data_type=${data_type?param missing - data_type is ATAC or DNASE}
reference_fasta=${reference_fasta?param missing - reference genome file missing}
chrom_sizes=${chrom_sizes?param missing - reference genome chrom sizes file missing}
peaks=${peaks?param missing - peaks bed file missing}
nonpeaks=${nonpeaks?param missing - nonpeaks bed file missing}
fold=${fold?param missing - fold json missing}
bias_model=${bias_model?param missing - bias_model .h5 file missing}
output_dir=${output_dir?param missing - output_dir path missing}

seed=${seed:-1234} # optional
pwm_f=${pwm_f} #optional

## output dirs

if [[ ! -e $output_dir ]]; then
    mkdir $output_dir
fi


if [[ ! -e $output_dir/logs ]]; then
    mkdir $output_dir/logs
fi

if [[ ! -e $output_dir/intermediates ]]; then
    mkdir $output_dir/intermediates
fi

if [[ ! -e $output_dir/intermediates ]]; then
    mkdir $output_dir/intermediates
fi


if [[ ! -e $output_dir/models ]]; then
    mkdir $output_dir/models
fi


if [[ ! -e $output_dir/evaluation ]]; then
    mkdir $output_dir/evaluation
fi



# intermediate files

bigwig_prefix=$output_dir/intermediates/data
bigwig_path=$bigwig_prefix"_unstranded.bw"




# Make bigwigs from bam

function timestamp {
    # Function to get the current time with the new line character
    # removed 
    
    # current time
    date +"%Y-%m-%d_%H-%M-%S" | tr -d '\n'
}

logfile=$output_dir/logs/"preprocessing.log"
touch $logfile

echo $( timestamp ): "chrombpnet_makebigwig -g $reference_fasta -ibam $in_bam -c $chrom_sizes -o $bigwig_prefix -d  $data_type" | tee -a $logfile
chrombpnet_makebigwig -g $reference_fasta -ibam $in_bam -c $chrom_sizes -o $bigwig_prefix -d  $data_type
echo $( timestamp ): "chrombpnet_pwm_from_bigwig -i $bigwig_prefix_unstranded.bw -g $reference_fasta -o $bigwig_prefix_bias_pwm -c chr20 -cz $chrom_sizes" | tee -a $logfile
chrombpnet_pwm_from_bigwig -i $bigwig_prefix"_unstranded.bw" -g $reference_fasta -o $output_dir/evaluation/"pwm_from_input" -c "chr20" -cz $chrom_sizes 


# Train ChromBPNet model


# defaults
inputlen=2114
outputlen=1000
filters=512
n_dilation_layers=8
negative_sampling_ratio=0.1

function timestamp {
    # Function to get the current time with the new line character
    # removed 
    
    # current time
    date +"%Y-%m-%d_%H-%M-%S" | tr -d '\n'
}

#path to pwm file
if [ -z "$pwm_f" ]
then
    TAB="$(printf '\t')"
    if [["$data_type" = "DNASE" ]] ; then
	echo "No pwm file supplied, using default for DNASE"
	tee  $output_dir/intermediates/motif_to_pwm.default.tsv <<EOF
dnase_1${TAB}TTTACAAGTCCA
dnase_2${TAB}TGTACTTACGAA
EOF
    elif [[ "$data_type" = "ATAC"  ]] ; then
	echo "No pwm file supplied, using default for ATAC"
	tee  $output_dir/intermediates/motif_to_pwm.default.tsv <<EOF
tn5_1${TAB}GCACAGTACAGAGCTG
tn5_2${TAB}GTGCACAGTTCTAGAGTGTGCAG
tn5_3${TAB}CCTCTACACTGTGCAGAA
tn5_4${TAB}GCACAGTTCTAGACTGTGCAG
tn5_5${TAB}CTGCACAGTGTAGAGTTGTGC
EOF
    else
	echo "ERROR: unknown data type " $data_type | tee -a $logfile
    fi    
    pwm_f=$output_dir/intermediates/motif_to_pwm.default.tsv
fi


logfile=$output_dir"/logs/train_chrombpnet_model.log"
touch $logfile


# this script does the following -  
# (1) filters your peaks/nonpeaks (removes outliers and removes edge cases and creates a new filtered set)
# (2) scales the given bias model on the non-peaks
# (3) Calculates the counts loss weight 
# (4) Creates a TSV file that can be loaded into the next step
echo $( timestamp ): "chrombpnet_hyperparams \\
       --genome=$reference_fasta \\
       --bigwig=$bigwig_path \\
       --peaks=$peaks \\
       --nonpeaks=$nonpeaks \\
       --outlier_threshold=0.99 \\
       --chr_fold_path=$fold \\
       --negative_sampling_ratio=$negative_sampling_ratio \\
       --inputlen=$inputlen \\
       --outputlen=$outputlen \\
       --max_jitter=500 \\
       --filters=$filters \\
       --n_dilation_layers=$n_dilation_layers \\
       --bias_model_path=$bias_model \\
       --output_dir=$output_dir/intermediates/ " | tee -a $logfile
chrombpnet_hyperparams \
    --genome=$reference_fasta \
    --bigwig=$bigwig_path \
    --peaks=$peaks \
    --nonpeaks=$nonpeaks \
    --outlier_threshold=0.99 \
    --chr_fold_path=$fold \
    --negative_sampling_ratio=$negative_sampling_ratio \
    --inputlen=$inputlen \
    --outputlen=$outputlen \
    --max_jitter=500 \
    --filters=$filters \
    --n_dilation_layers=$n_dilation_layers \
    --bias_model_path=$bias_model \
    --output_dir=$output_dir/intermediates/ | tee -a $logfile

## this script does the following -  
# (1) trains a model on the given peaks/nonpeaks
# (2) The parameters file input to this script should be TSV seperatedp
chrombpnet_with_bias_model_path=`which chrombpnet_with_bias_model.py`
echo $( timestamp ): "chrombpnet_train \\
       --genome=$reference_fasta \\
       --bigwig=$bigwig_path \\
       --peaks=$output_dir/intermediates/filtered.peaks.bed \\
       --nonpeaks=$output_dir/intermediates/filtered.nonpeaks.bed \\
       --params=$output_dir/intermediates/chrombpnet_model_params.tsv \\
       --output_prefix=$output_dir/models/chrombpnet \\
       --chr_fold_path=$fold \\
       --seed=$seed \\
       --batch_size=64 \\
       --architecture_from_file=$chrombpnet_with_bias_model_path \\
       --trackables logcount_predictions_loss loss logits_profile_predictions_loss val_logcount_predictions_loss val_loss val_logits_profile_predictions_loss" | tee -a $logfile

chrombpnet_train \
    --genome=$reference_fasta \
    --bigwig=$bigwig_path \
    --peaks=$output_dir/intermediates/filtered.peaks.bed \
    --nonpeaks=$output_dir/intermediates/filtered.nonpeaks.bed \
    --params=$output_dir/intermediates/chrombpnet_model_params.tsv \
    --output_prefix=$output_dir/models/chrombpnet \
    --chr_fold_path=$fold \
    --seed=$seed \
    --batch_size=64 \
    --architecture_from_file=$chrombpnet_with_bias_model_path \
    --trackables logcount_predictions_loss loss logits_profile_predictions_loss val_logcount_predictions_loss val_loss val_logits_profile_predictions_loss | tee -a $logfile

#predictions and metrics on the chrombpnet model trained
echo $( timestamp ): "chrombpnet_predict \\
        --genome=$reference_fasta \\
        --bigwig=$bigwig_path \\
        --peaks=$output_dir/intermediates/filtered.peaks.bed \\
        --chr_fold_path=$fold \\
        --inputlen=$inputlen \\
        --outputlen=$outputlen \\
        --output_prefix=$output_dir/evaluation/chrombpnet \\
        --batch_size=256 \\
        --model_h5=$output_dir/models/chrombpnet.h5" | tee -a $logfile
chrombpnet_predict \
    --genome=$reference_fasta \
    --bigwig=$bigwig_path \
    --peaks=$output_dir/intermediates/filtered.peaks.bed \
    --chr_fold_path=$fold \
    --inputlen=$inputlen \
    --outputlen=$outputlen \
    --output_prefix=$output_dir/evaluation/chrombpnet \
    --batch_size=256 \
    --model_h5=$output_dir/models/chrombpnet.h5 | tee -a $logfile

#predictions and metrics on the bias model trained
echo $( timestamp ): "chrombpnet_predict \\
        --genome=$reference_fasta \\
        --bigwig=$bigwig_path \\
        --peaks=$output_dir/intermediates/filtered.peaks.bed \\
        --chr_fold_path=$fold \\
        --inputlen=$inputlen \\
        --outputlen=$outputlen \\
        --output_prefix=$output_dir/evaluation/bias \\
        --batch_size=256 \\
        --model_h5=$output_dir/intermediates/bias_model_scaled.h5" | tee -a $logfile
chrombpnet_predict \
    --genome=$reference_fasta \
    --bigwig=$bigwig_path \
    --peaks=$output_dir/intermediates/filtered.peaks.bed \
    --chr_fold_path=$fold \
    --inputlen=$inputlen \
    --outputlen=$outputlen \
    --output_prefix=$output_dir/evaluation/bias \
    --batch_size=256 \
    --model_h5=$output_dir/intermediates/bias_model_scaled.h5 | tee -a $logfile

# marginal footprinting
mkdir $output_dir/evaluation/footprints
if [[ "$data_type" = "DNASE" ]] ; then
    echo $( timestamp ): "mkdir $output_dir/evaluation/footprints" | tee -a $logfile
    echo $( timestamp ): "chrombpnet_marginal_footprints \\
    	     -g $reference_fasta \\
             -r $output_dir/intermediates/filtered.nonpeaks.bed \\
             --chr_fold_path=$fold \\
             -m $output_dir/models/chrombpnet_nobias.h5 \\
             -bs 512 \\
             -o $output_dir/evaluation/footprints/corrected \\
             -pwm_f $pwm_f "| tee -a $logfile
    chrombpnet_marginal_footprints \
	-g $reference_fasta \
	-r $output_dir/intermediates/filtered.nonpeaks.bed \
	--chr_fold_path=$fold \
	-m $output_dir/models/chrombpnet_nobias.h5 \
	-bs 512 \
	-o $output_dir/evaluation/footprints/corrected \
	-pwm_f $pwm_f | tee -a $logfile
elif [[ "$data_type" = "ATAC"  ]] ; then
    echo $( timestamp ): "mkdir $output_dir/evaluation/footprints" | tee -a $logfile
    echo $( timestamp ): "chrombpnet_marginal_footprints \\
    	-g $reference_fasta \\                     
        -r $output_dir/intermediates/filtered.nonpeaks.bed \\
        --chr_fold_path=$fold \\
        -m $output_dir/models/chrombpnet_nobias.h5 \\
        -bs 512 \\
        -o $output_dir/evaluation/footprints/corrected \\
        -pwm_f $pwm_f"  | tee -a $logfile
    chrombpnet_marginal_footprints \
	-g $reference_fasta \
	-r $output_dir/intermediates/filtered.nonpeaks.bed \
	--chr_fold_path=$fold \
	-m $output_dir/models/chrombpnet_nobias.h5 \
	-bs 512 \
	-o $output_dir/evaluation/footprints/corrected \
	-pwm_f $pwm_f | tee -a $logfile
else
    echo "ERROR: unknown data type " $data_type | tee -a $logfile
fi

# marginal footprinting bias model
if [[ "$data_type" = "DNASE" ]] ; then
    echo $( timestamp ): "mkdir $output_dir/evaluation/footprints" | tee -a $logfile
    echo $( timestamp ): "chrombpnet_marginal_footprints \\
        -g $reference_fasta \\
        -r $output_dir/intermediates/filtered.nonpeaks.bed \\
        --chr_fold_path=$fold \\
        -m $output_dir/intermediates/bias_model_scaled.h5 \\
        -bs 512 \\
        -o $output_dir/evaluation/footprints/bias \\
        -pwm_f $pwm_f"  | tee -a $logfile
    chrombpnet_marginal_footprints \
	-g $reference_fasta \
	-r $output_dir/intermediates/filtered.nonpeaks.bed \
	--chr_fold_path=$fold \
	-m $output_dir/intermediates/bias_model_scaled.h5 \
	-bs 512 \
	-o $output_dir/evaluation/footprints/bias \
	-pwm_f $pwm_f | tee -a $logfile
elif [[ "$data_type" = "ATAC" ]] ; then
    echo $( timestamp ): "mkdir $output_dir/evaluation/footprints" | tee -a $logfile
    echo $( timestamp ): "chrombpnet_marginal_footprints \\
    	     -g $reference_fasta \\
             -r $output_dir/intermediates/filtered.nonpeaks.bed \\
             --chr_fold_path=$fold \\
             -m $output_dir/intermediates/bias_model_scaled.h5 \\
             -bs 512 \\
             -o $output_dir/evaluation/footprints/bias \\
             -pwm_f $pwm_f" | tee -a $logfile
    chrombpnet_marginal_footprints \
	-g $reference_fasta \
	-r $output_dir/intermediates/filtered.nonpeaks.bed \
	--chr_fold_path=$fold \
	-m $output_dir/intermediates/bias_model_scaled.h5 \
	-bs 512 \
	-o $output_dir/evaluation/footprints/bias \
	-pwm_f $pwm_f  | tee -a $logfile
else
    echo "ERROR: unknown data type " $data_type | tee -a $logfile
fi


## interpret the model

function timestamp {
    # Function to get the current time with the new line character
    # removed 
    
    # current time
    date +"%Y-%m-%d_%H-%M-%S" | tr -d '\n'
}


shuf --random-source=<(yes 42) -n 30000 $output_dir/intermediates/filtered.peaks.bed > $output_dir/intermediates/30K.subsample.peaks.bed
interpret_regions=$output_dir/intermediates/30K.subsample.peaks.bed


if [[ ! -e $output_dir/evaluation/interpret/ ]]; then
    mkdir $output_dir/evaluation/interpret/
fi

## deepshap run

logfile=$output_dir/logs/"interpretation.log"
touch $logfile

echo $( timestamp ): "chrombpnet_deepshap \
    --genome=$reference_fasta \
    --regions=$interpret_regions \
    --output_prefix=$output_dir/evaluation/interpret/corrected \
    --model_h5=$output_dir/models/chrombpnet_nobias.h5 \
" | tee -a $logfile

chrombpnet_deepshap \
    --genome=$reference_fasta \
    --regions=$interpret_regions \
    --output_prefix=$output_dir/evaluation/interpret/corrected \
    --model_h5=$output_dir/models/chrombpnet_nobias.h5  | tee -a $logfile

## modisco run


echo $( timestamp ): "modisco motifs -i $output_dir/evaluation/interpret"/corrected.profile_scores.h5" -n 50000 -o $output_dir/evaluation/interpret"/modisco_results_allChroms_profile.hdf5" -w 500" | tee -a $logfile
modisco motifs -i $output_dir/evaluation/interpret"/corrected.profile_scores.h5" -n 50000 -o $output_dir/evaluation/interpret"/modisco_results_allChroms_profile.hdf5" -w 500  | tee -a $logfile
echo $( timestamp ): "modisco motifs -i $output_dir/evaluation/interpret"/corrected.counts_scores.h5" -n 50000 -o $output_dir/evaluation/interpret"/modisco_results_allChroms_counts.hdf5" -w 500" | tee -a $logfile
modisco motifs -i $output_dir/evaluation/interpret"/corrected.counts_scores.h5" -n 50000 -o $output_dir/evaluation/interpret"/modisco_results_allChroms_counts.hdf5" -w 500  | tee -a $logfile


meme_dir=$(chrombpnet_srcdir)"/../data"

echo $( timestamp ): "modisco report -i $output_dir/evaluation/interpret"/modisco_results_allChroms_profile.hdf5" -o  $output_dir/evaluation/interpret/modisco_reports_profile/ -s "./" -m $meme_dir/motifs.meme.txt" | tee -a $logfile
modisco report -i $output_dir/evaluation/interpret"/modisco_results_allChroms_profile.hdf5" -o  $output_dir/evaluation/interpret/modisco_reports_profile/ -s "./" -m $meme_dir/motifs.meme.txt  | tee -a $logfile
echo $( timestamp ): "modisco report -i $output_dir/evaluation/interpret"/modisco_results_allChroms_counts.hdf5" -o  $output_dir/evaluation/interpret/modisco_reports_counts/ -s "./" -m $meme_dir/motifs.meme.txt" | tee -a $logfile
modisco report -i $output_dir/evaluation/interpret"/modisco_results_allChroms_counts.hdf5" -o  $output_dir/evaluation/interpret/modisco_reports_counts/ -s "./" -m $meme_dir/motifs.meme.txt  | tee -a $logfile


echo $( timestamp ): "chrombpnet_convert_html_to_pdf -i $output_dir/evaluation/interpret/modisco_reports_profile/motifs.html -o $output_dir/evaluation/profile_motifs.pdf" | tee -a $logfile
chrombpnet_convert_html_to_pdf -i $output_dir/evaluation/interpret/modisco_reports_profile/motifs.html -o $output_dir/evaluation/profile_motifs.pdf  | tee -a $logfile
echo $( timestamp ): "chrombpnet_convert_html_to_pdf -i $output_dir/evaluation/interpret/modisco_reports_counts/motifs.html -o $output_dir/evaluation/counts_motifs.pdf" | tee -a $logfile
chrombpnet_convert_html_to_pdf -i $output_dir/evaluation/interpret/modisco_reports_counts/motifs.html -o $output_dir/evaluation/counts_motifs.pdf  | tee -a $logfile




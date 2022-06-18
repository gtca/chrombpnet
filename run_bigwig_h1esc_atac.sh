chrombpnet_nb=results/chrombpnet/ATAC_PE/H1ESC/nautilus_runs_jun16/H1ESC_05.09.2022_bias_128_4_1234_0.8_fold_0/chrombpnet_model/chrombpnet_wo_bias.h5 
chrombpnet=results/chrombpnet/ATAC_PE/H1ESC/nautilus_runs_jun16/H1ESC_05.09.2022_bias_128_4_1234_0.8_fold_0/chrombpnet_model/chrombpnet.h5
bias=results/chrombpnet/ATAC_PE/H1ESC/nautilus_runs_jun16/H1ESC_05.09.2022_bias_128_4_1234_0.8_fold_0/chrombpnet_model/bias_model_scaled.h5
celline=H1ESC
gpu=0

main_dir=results/chrombpnet/ATAC_PE/H1ESC/nautilus_runs_jun16/H1ESC_05.09.2022_bias_128_4_1234_0.8_fold_0/
output_dir=$main_dir/interpret/
mkdir $output_dir

#merge h1esc peaks form atac and dnase
#atac_peaks=/oak/stanford/groups/akundaje/projects/chrombpnet/model_inputs/ATAC/optimal_overlap_peaks/H1ESC.overlap.optimal_peak.narrowPeak.gz
#dnase_peaks=/oak/stanford/groups/akundaje/projects/chrombpnet/model_inputs/DNASE/optimal_overlap_peaks/H1ESC.overlap.optimal_peak.narrowPeak.gz
#zcat $atac_peaks $dnase_peaks | uniq > results/chrombpnet/h1esc.merged.atac.dnase.peaks.bed

regions=results/chrombpnet/h1esc.merged.atac.dnase.peaks.bed
bash make_bigwig_new.sh $chrombpnet_nb $chrombpnet $bias $celline $gpu $regions $output_dir



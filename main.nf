#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

/*
VirReport workflow
Roberto Barrero, 14/03/2019
Desmond Schmidt, 2/7/2019
Converted to Nextflow by Craig Windell, 11/2020
Modified by Maely Gauthier, 2021-2023
*/

import java.util.*;
import java.util.stream.IntStream;
import java.util.stream.Collectors;

def helpMessage () {
    log.info """

    VirReport workflow
    Roberto Barrero, 14/03/2019
    Desmond Schmidt, 2/7/2019
    Converted to Nextflow by Craig Windell, 11/2020
    Modified by Maely Gauthier, 2021-2023

    Usage:

    Run the command
    nextflow run eresearchqut/virreport -profile ...

    Mandatory arguments:
       -profile '[docker, singularity]'             Profile to use. Choose docker or singularity

    Optional arguments:
      --indexfile '[path/to/file]'                  Path to the csv file that contains the list of
                                                    samples to be analysed by this pipeline.
                                                    'index.csv'
      Contents of indexfile csv:
        sampleid,samplepath
        MT019,/user/folder/MT019_sRNA.fastq

      --blast_db_dir '[path/to/files]'                  Path to the blast NT and/or NR database file base name
                                                        [none]

      --blast_viral_db                                  Run blastn and megablast homology search on cap3 de novo assembly against a virus and viroid database
                                                        [False]

      --blast_viral_nt_db '[path/to/file]'              Path to the viral nucleotide database file base name. Required if --blast_viral_db option is specified
                                                        [none]
      
      --blastn_evalue '[value]'                         Blastn evalue.
                                                        '0.0001'

      --blastn_method ['blastn/megablast']              Specify blastn homology search on cap3 de novo assembly againts NCBI NT
                                                        [default megablast]
                    
      --blastx [True/False]                             Run blastX againts NCBI NR
                                                        [False]

      --bowtie_db_dir                                   Path to the bowtie indices (for RNA source step and filtering of non-informative reads)
      
      --cap3_len '[value]'                              Trim value used in the CAP3 step.
                                                        '40'

      --contamination_detection [True/False]            Run false positive prediction due to cross-sample contamination for detections 
                                                        obtained via blastn search against NT
                                                        [False]

      --contamination_detection_viral_db                Run false positive prediction due to cross-sample contamination for detections 
                                                        obtained via blastn search against a viral database
                                                        [False]
      
      --contamination_flag '[value]'                    Threshold value to predict false positives due to cross-sample contamination. 
                                                        Required if --contamination_detection option is specified
                                                        '0.01'

      --dedup                                           Use UMI-tools dedup to remove duplicate reads  
      
      --maxlen '[value]'                                Maximum read length to extract
      ['22']

      --merge_lane                                      Specify this option if sequencing was peformed on several flow cells and 2 or more fastq files were generated for one sample and require to be merged

      --minlen '[value]'                                Minimum read length to extract
      ['21']
      
      --orf_circ_minsize '[value]'                      The value of minsize for getorf -circular
                                                        '75'
      
      --orf_minsize '[value]'                           The value of minsize for getorf
                                                        '75'

      --qualityfilter [True/False]                      Perform adapter and quality filtering of fastq files
                                                        [False]

      --rna_source_profile                              Evaluates the sRNA library content
                                                        [False]

      --spadesmem  '[value]'                            Memory usage for SPAdes de novo assembler
                                                        [60]               
      
      --targets [True/False]                            Filter the blastn results to viruses/viroids of interest
                                                        [False]

      --targets_file '[path/to/folder]'                 File specifying the name of the viruses/viroids of interest to filter from the blast results output
                                                        ['Targetted_Viruses_Viroids.txt']
      
      --tblastn_evalue                                  tblastn evalue. Required if --tblatsn option is specified
                                                        '0.0001'
      
      --virusdetect [True/False]                        Run VirusDetect
                                                        [False]
      
      --virusdetect_db_path '[path/to/filebasename]'    Path to the virusdetect blast virus database base name
                                                        [none]
      
    ####
    Internal SSG usage only
      --diagno                                          Additional information will be added to each viral detection to facilitate interpretation 
                                                        [False]
      --synthetic_oligos                                Reads will be aligned to specific synthetic oligos
                                                        [False]
      --sampleinfo                                      Appends additional sample information to final summary to facilitate diagnostics reporting
                                                        [False]
      --sampleinfo_path                                 Path_to_sample_info to be appended
                                                        [none]
      --samplesheet_path                                Path_to_sample_sheet to be appended
                                                        [none]

    """.stripIndent()
}
// Show help message
if (params.help) {
    helpMessage()
    exit 0
}
if (params.blast_db_dir != null) {
    blastn_db_name = "${params.blast_db_dir}/nt"
    blastp_db_name = "${params.blast_db_dir}/nr"
}
if (params.blast_viral_db_path != null) {
    blast_viral_db_name = file(params.blast_viral_db_path).name
    blast_viral_db_dir = file(params.blast_viral_db_path).parent
}
if (params.virusdetect_db_path != null) {
    virusdetect_db_dir = file(params.virusdetect_db_path).parent
}
size_range = "${params.minlen}-${params.maxlen}nt"
if (params.sampleinfo_path != null) {
    sampleinfo_dir = file(params.sampleinfo_path).parent
    sampleinfo_name = file(params.sampleinfo_path).name
}
if (params.samplesheet_path != null) {
    samplesheet_dir = file(params.samplesheet_path).parent
    samplesheet_name = file(params.samplesheet_path).name
}

switch (workflow.containerEngine) {
    case "docker":
        bindbuild = "";
        if (params.blast_viral_db_path != null) {
            bindbuild = "-v ${blast_viral_db_dir}:${blast_viral_db_dir} "
        }
        if (params.blast_db_dir != null) {
            bindbuild = (bindbuild + "-v ${params.blast_db_dir}:${params.blast_db_dir} ")
        }
        if (params.bowtie_db_dir != null) {
            bindbuild = (bindbuild + "-v ${params.bowtie_db_dir}:${params.bowtie_db_dir} ")
        }
        if (params.virusdetect_db_path != null) {
            bindbuild = (bindbuild + "-v ${virusdetect_db_dir}:${virusdetect_db_dir} ")
        }
        if (params.sampleinfo_path != null) {
            bindbuild = (bindbuild + "-v ${sampleinfo_dir}:${sampleinfo_dir} ")
        }
        if (params.samplesheet_path != null) {
            bindbuild = (bindbuild + "-v ${samplesheet_dir}:${samplesheet_dir} ")
        }
        bindOptions = bindbuild;
        break;
    case "singularity":
        bindbuild = "";
        if (params.blast_viral_db_path != null) {
            bindbuild = "-B ${blast_viral_db_dir} "
        }
        if (params.blast_db_dir != null) {
            bindbuild = (bindbuild + "-B ${params.blast_db_dir} ")
        }
        if (params.bowtie_db_dir != null) {
            bindbuild = (bindbuild + "-B ${params.bowtie_db_dir} ")
        }
        if (params.virusdetect_db_path != null) {
            bindbuild = (bindbuild + "-B ${virusdetect_db_dir} ")
        }
        if (params.sampleinfo_path != null) {
            bindbuild = (bindbuild + "-B ${sampleinfo_dir} ")
        }
        if (params.samplesheet_path != null) {
            bindbuild = (bindbuild + "-B ${samplesheet_dir} ")
        }
        bindOptions = bindbuild;
        break;
    default:
        bindOptions = "";
}

process FASTQC_RAW {
    tag "$sampleid"
    publishDir "${params.outdir}/00_quality_filtering/${sampleid}", mode: 'link'

    input:
    tuple val(sampleid), file(fastqfile_path)
    
    output:
    path("*_fastqc.{zip,html}")

    script:
    """
    fastqc --quiet --threads ${task.cpus} ${fastqfile_path}
    """
}

process MERGE_LANES {
    tag "$sampleid"

    input:
    tuple val(sampleid), file(samplepath)
    
    output:
    tuple val(sampleid), file("${sampleid}_R1.merged.fastq.gz"), emit: merged

    script:
    if (params.merge_lane) {
        samplepathList = samplepath.collect{it.toString()}
        if (samplepathList.size > 1 ) {
        """
        cat ${samplepath} > ${sampleid}_R1.merged.fastq.gz
        """
        }
    } else {
        """
        ln ${samplepath} ${sampleid}_R1.merged.fastq.gz
        """
    }
}

//This step takes > 1h to run for the large flow cells
process ADAPTER_TRIMMING {
    label "setting_6"
    tag "$sampleid"
    publishDir "${params.outdir}/00_quality_filtering/${sampleid}", mode: 'link', overwrite: true, pattern: "*{log,json,html,trimmed.fastq.gz,zip,html,pdf,txt}"

    input:
    tuple val(sampleid), path(fastqfile)

    output:
    path("${sampleid}_umi_tools.log")
    path("${sampleid}_truseq_adapter_cutadapt.log")
    path("${sampleid}_umi_tools.log"), emit: umi_tools_results
    tuple val(sampleid), path("${sampleid}_umi_cleaned.fastq.gz"), emit: adapter_trimmed
    

    script:
    """
    #Checks Illumina seq adapters have been removed
    cutadapt -j ${task.cpus} \
            --no-indels \
            -a "AGATCGGAAGAGCACACGTCTGAACTCCAGTCA;min_overlap=12" \
            -g "ACACTCTTTCCCTACACGACGCTCTTCCGATCT;min_overlap=9" \
            --times 2 \
            -o ${sampleid}_trimmed.fastq.gz \
            ${fastqfile} > ${sampleid}_truseq_adapter_cutadapt.log

    umi_tools extract --extract-method=regex \
                        --bc-pattern=".+(?P<discard_1>AACTGTAGGCACCATCAAT){s<=2}(?P<umi_1>.{12})\$" \
                        -I ${sampleid}_trimmed.fastq.gz \
                        -S ${sampleid}_umi_cleaned.fastq.gz > ${sampleid}_umi_tools.log
    
    rm ${sampleid}_trimmed.fastq.gz
    """
}

process QUAL_TRIMMING_AND_QC {
    label "setting_3"
    tag "$sampleid"
    publishDir "${params.outdir}/00_quality_filtering/${sampleid}", mode: 'link', overwrite: true, pattern: "*{log,json,html,trimmed.fastq.gz,zip,html,png,pdf,txt}"
    
    input:
    tuple val(sampleid), path(fastqfile)

    output:
    file "*_fastqc.{zip,html}"
    file "${sampleid}_fastp.json"
    file "${sampleid}_fastp.html"
    file "${sampleid}_read_length_dist.pdf"
    file "${sampleid}_read_length_dist.png"
    file "${sampleid}_read_length_dist.txt"
    file "${sampleid}_quality_trimmed.fastq.gz"
    file "${sampleid}_qual_filtering_cutadapt.log"

    path("${sampleid}_qual_filtering_cutadapt.log"), emit: cutadapt_qual_filt_results
    tuple val(sampleid), path("${sampleid}_quality_trimmed.fastq"), emit: qual_trimmed
    path("${sampleid}_fastp.json"), emit: fastp_results
    path("${sampleid}_read_length_dist.txt"), emit: read_length_dist_results

    script:
    """
    cutadapt -j ${task.cpus} \
            --trim-n --max-n 0 -m 18 -q 30 \
            -o ${sampleid}_quality_trimmed.fastq \
            ${sampleid}_umi_cleaned.fastq.gz > ${sampleid}_qual_filtering_cutadapt.log

    pigz --best --force -p ${task.cpus} -r ${sampleid}_quality_trimmed.fastq -c > ${sampleid}_quality_trimmed.fastq.gz

    fastqc --quiet --threads ${task.cpus} ${sampleid}_quality_trimmed.fastq.gz

    fastp --in1=${sampleid}_quality_trimmed.fastq.gz --out1=${sampleid}_fastp_trimmed.fastq.gz \
        --disable_adapter_trimming \
        --disable_quality_filtering \
        --disable_length_filtering \
        --json=${sampleid}_fastp.json \
        --html=${sampleid}_fastp.html \
        --thread=${task.cpus}
    
    #derive distribution for quality filtered reads > 5 bp long
    cutadapt -j ${task.cpus} \
            --trim-n --max-n 0 -m 5 -q 30 \
            -o ${sampleid}_quality_trimmed_temp.fastq \
            ${sampleid}_umi_cleaned.fastq.gz
    
    fastq2fasta.pl ${sampleid}_quality_trimmed_temp.fastq > ${sampleid}_quality_trimmed.fasta
    
    read_length_dist.py --input ${sampleid}_quality_trimmed.fasta
    
    mv ${sampleid}_quality_trimmed.fasta_read_length_dist.txt ${sampleid}_read_length_dist.txt
    mv ${sampleid}_quality_trimmed.fasta_read_length_dist.png ${sampleid}_read_length_dist.png
    mv ${sampleid}_quality_trimmed.fasta_read_length_dist.pdf ${sampleid}_read_length_dist.pdf
    rm ${sampleid}_quality_trimmed_temp.fastq
    """
}

process RNA_SOURCE_PROFILE {
    label "setting_2"
    tag "$sampleid"
    publishDir "${params.outdir}/00_quality_filtering/${sampleid}", mode: 'link',overwrite: true, pattern: "*{log}"
    containerOptions "${bindOptions}"

    input:
    tuple val(sampleid), file(fastqfile)
    
    output:
    path("${sampleid}_bowtie.log")
    path("${sampleid}_bowtie.log"), emit: rna_source_bowtie_results

    script:
    """
    cutadapt -j ${task.cpus} \
            --trim-n --max-n 0 -m 15 -q 30 \
            -o ${sampleid}_quality_trimmed_temp2.fastq \
            ${sampleid}_umi_cleaned.fastq.gz

    #derive distribution for quality filtered reads > 15 bp bp long
    echo ${sampleid} > ${sampleid}_bowtie.log;

    count=1
    for rnatype in rRNA plant_pt_mt_other_genes miRNA plant_tRNA plant_noncoding artefacts plant_virus_viroid; do
        if [[ \${count} == 1 ]]; then
            fastqfile=${sampleid}_quality_trimmed_temp2.fastq
        fi
        echo \${rnatype} alignment: >> ${sampleid}_bowtie.log;
        bowtie -q -v 2 -k 1 -p ${task.cpus} \
            --un ${sampleid}_\${rnatype}_cleaned_sRNA.fq \
            -x ${params.bowtie_db_dir}/\${rnatype} \
            \${fastqfile} \
            ${sampleid}_\${rnatype}_match 2>>${sampleid}_bowtie.log
        count=\$((count+1))

        if [[ \${count}  > 1 ]]; then
            fastqfile=${sampleid}_\${rnatype}_cleaned_sRNA.fq
        fi
        rm ${sampleid}_\${rnatype}_match;
    done
    
    rm *cleaned_sRNA.fq
"""
}

process RNA_SOURCE_PROFILE_REPORT {
    publishDir "${params.outdir}/00_quality_filtering/qc_report", mode: 'link'
    containerOptions "${bindOptions}"

    input:
    path("*bowtie.log")

    output:
    path("read_origin_pc_summary*.txt")
    path("read_origin_counts*.txt")
    path("read_RNA_source*.pdf")
    path("read_RNA_source*.png")
    path("read_origin_detailed_pc*.txt")

    script:
    """
    rna_source_summary.py
    """
}

process DERIVE_USABLE_READS {
    label "setting_4"
    tag "$sampleid"
    publishDir "${params.outdir}/00_quality_filtering/${sampleid}", mode: 'link', overwrite: true, pattern: "*{.log,.fastq.gz}"
    containerOptions "${bindOptions}"
    
    input:
    tuple val(sampleid), file(fastqfile)
    
    output:
    path("${sampleid}*_cutadapt.log")
    path("${sampleid}_blacklist_filter.log")
    path("${sampleid}_${params.minlen}-${params.maxlen}nt.fastq.gz")
    
    tuple val(sampleid),
          path(fastqfile),
          path("${sampleid}_${params.minlen}-${params.maxlen}nt.fastq"),
          emit: usable_reads
    
    path("*_18-25nt_cutadapt.log"), emit: cutadapt_18_25nt_results
    path("*_21-22nt_cutadapt.log"), emit: cutadapt_21_22nt_results
    path("*_24nt_cutadapt.log"), emit: cutadapt_24nt_results
    path("*_blacklist_filter.log"), emit: bowtie_usable_read_results

    script:
    """
    bowtie -q -v 1 \
            -k 1 --un ${sampleid}_cleaned.fastq -p ${task.cpus} \
            -x ${params.bowtie_db_dir}/blacklist \
            ${fastqfile} \
            ${sampleid}_blacklist_match 2>${sampleid}_blacklist_filter.log

    cutadapt -j ${task.cpus} -m 18 -M 25 -o ${sampleid}_18-25nt.fastq.gz ${sampleid}_cleaned.fastq > ${sampleid}_18-25nt_cutadapt.log
    cutadapt -j ${task.cpus} -m 21 -M 22 -o ${sampleid}_21-22nt.fastq ${sampleid}_cleaned.fastq > ${sampleid}_21-22nt_cutadapt.log
    cutadapt -j ${task.cpus} -m 24 -M 24 -o ${sampleid}_24nt.fastq.gz ${sampleid}_cleaned.fastq > ${sampleid}_24nt_cutadapt.log
    if [[ ${params.minlen} != 21 ]] || [[ ${params.maxlen} != 22 ]]; then
        cutadapt -j ${task.cpus} -m ${params.minlen} -M ${params.maxlen} -o ${sampleid}_${params.minlen}-${params.maxlen}nt.fastq ${sampleid}_cleaned.fastq > ${sampleid}_${params.minlen}-${params.maxlen}nt_cutadapt.log
    fi

    rm ${sampleid}_24nt.fastq.gz ${sampleid}_18-25nt.fastq.gz

    pigz --best --force -p ${task.cpus} -r ${sampleid}_${params.minlen}-${params.maxlen}nt.fastq -c > ${sampleid}_${params.minlen}-${params.maxlen}nt.fastq.gz
    """
}
/*
file("*qual_filtering_cutadapt.log")
    file("*fastp.json")
    file("*_read_length_dist.txt")
    file("*_18-25nt_cutadapt.log")
    file("*_21-22nt_cutadapt.log")
    file("*_24nt_cutadapt.log")
    file("*_blacklist_filter.log") 
    file("*_umi_tools.log")
    */

process QCREPORT {
    publishDir "${params.outdir}/00_quality_filtering/qc_report", mode: 'link'
    containerOptions "${bindOptions}"

    input:
    path multiqc_files

    output:
    path("run_qc_report*.txt")
    path("run_read_size_distribution*.pdf")
    path("run_read_size_distribution*.png")
    
    script:
    """
    if [[ ${params.sampleinfo} == true ]]; then
        seq_run_qc_report.py --sampleinfopath ${params.sampleinfo_path} --samplesheetpath ${params.samplesheet_path}
    else
        seq_run_qc_report.py 
    fi

    grouped_bar_chart.py
    """
}

process READPROCESSING {
    tag "$sampleid"
    publishDir "${params.outdir}/01_VirReport/${sampleid}/assembly", mode: 'link'

    input:
    tuple val(sampleid), file(fastqfile)

    output:
    path("${sampleid}_${size_range}_cutadapt.log")
    path("${sampleid}_${size_range}.fastq")
    tuple val(sampleid),
          path("unzipped.fastq"),
          path("${sampleid}_${size_range}.fastq"),
          emit: fastq

    script:
    """
    if [[ ${fastqfile} == *.gz ]];
    then
        gunzip -c ${fastqfile} > unzipped.fastq
    else
        ln ${fastqfile} unzipped.fastq
    fi

    cutadapt -j ${task.cpus} -m ${params.minlen} -M ${params.maxlen} -o ${sampleid}_${size_range}.fastq unzipped.fastq > ${sampleid}_${size_range}_cutadapt.log
    """
}

// This process performs separate velvet and SPAdes de novo assemblies 
// After merging the assemblies, the contigs are collapsed using cap3
process DENOVO_ASSEMBLY {
    publishDir "${params.outdir}/01_VirReport/${sampleid}/assembly", mode: 'link', overwrite: true, pattern: "*{fasta,log}"
    tag "$sampleid"
    label "setting_1"

    input:
    tuple val(sampleid), file(fastqfile), file(fastq_filt_by_size)

    output:
    file "${sampleid}_velvet_assembly_${size_range}.fasta"
    file "${sampleid}_velvet_log"
    file "${sampleid}_spades_assembly_${size_range}.fasta"
    file "${sampleid}_spades_log"
    file "${sampleid}_cap3_${size_range}.fasta"

    tuple val(sampleid),
          file(fastqfile),
          file(fastq_filt_by_size),
          file("${sampleid}_cap3_${size_range}.fasta"),
          emit: assembly_for_blastn

    tuple val(sampleid),
          file("${sampleid}_cap3_${size_range}.fasta"),
          emit: assembly_for_tblastn
    
    script:
    """
    #run velvet de novo assembler
    export OMP_NUM_THREADS=2
    echo 'Starting velvet de novo assembly';
    velveth ${sampleid}_velvet_${size_range}_k15 15 -short -fastq ${fastq_filt_by_size}
    velvetg ${sampleid}_velvet_${size_range}_k15 -exp_cov 2

    #edit contigs name and rename velvet assembly
    sed 's/>/>velvet_/' ${sampleid}_velvet_${size_range}_k15/contigs.fa > ${sampleid}_velvet_assembly_${size_range}.fasta
    cp ${sampleid}_velvet_${size_range}_k15/Log ${sampleid}_velvet_log
    
    #run spades de novo assembler
    spades.py --rna -t ${task.cpus} -k 19,21 -m ${params.spadesmem} -s ${fastq_filt_by_size} -o ${sampleid}_spades_k19_21
    #edit contigs name and rename spades assembly

    if [[ ! -s ${sampleid}_spades_k19_21/transcripts.fasta ]]
    then
        touch ${sampleid}_spades_assembly_${size_range}.fasta
    else
        sed 's/>/>spades_/' ${sampleid}_spades_k19_21/transcripts.fasta > ${sampleid}_spades_assembly_${size_range}.fasta
    fi

    cp ${sampleid}_spades_k19_21/spades.log ${sampleid}_spades_log

    #merge velvet and spades assemblies
    cat ${sampleid}_velvet_assembly_${size_range}.fasta ${sampleid}_spades_assembly_${size_range}.fasta > ${sampleid}_merged_spades_velvet_assembly_${size_range}.fasta
    
    #collapse derived contigs
    cap3 ${sampleid}_merged_spades_velvet_assembly_${size_range}.fasta -s 300 -j 31 -i 30 -p 90 -o 16
    cat ${sampleid}_merged_spades_velvet_assembly_${size_range}.fasta.cap.singlets ${sampleid}_merged_spades_velvet_assembly_${size_range}.fasta.cap.contigs > ${sampleid}_cap3_${size_range}_temp.fasta
    
    #retain only contigs > 30 bp long
    extract_seqs_rename.py ${sampleid}_cap3_${size_range}_temp.fasta ${params.cap3_len} \
                             | sed "s/CONTIG/${sampleid}_${params.minlen}-${params.maxlen}_/" \
                             | sed 's/|>/ |/' | awk '{print \$1}' \
                             > ${sampleid}_cap3_${size_range}.fasta
    """
}

process BLASTN_VIRAL_DB_CAP3 {
    label "setting_4"
    publishDir "${params.outdir}/01_VirReport/${sampleid}/blastn/viral_db", mode: 'link', overwrite: true, pattern: "*{vs_viral_db.bls,.txt}"
    tag "$sampleid"
    containerOptions "${bindOptions}"

    input:
    tuple val(sampleid), file(fastqfile), file(fastq_filt_by_size), file("${sampleid}_cap3_${size_range}.fasta")
    
    output:
    file "${sampleid}_cap3_${size_range}_blastn_vs_viral_db.bls"
    file "${sampleid}_cap3_${size_range}_megablast_vs_viral_db.bls"

    tuple val(sampleid),
          file(fastqfile),
          file(fastq_filt_by_size),
          file("${sampleid}_cap3_${size_range}.fasta"),
          file("${sampleid}_cap3_${size_range}_blastn_vs_viral_db.bls"),
          file("${sampleid}_cap3_${size_range}_megablast_vs_viral_db.bls"),
          emit: blast_results

    script:
    """
    #1. blastn search
    blastn -task blastn \
        -query ${sampleid}_cap3_${size_range}.fasta \
        -db ${blast_viral_db_dir}/${blast_viral_db_name} \
        -out ${sampleid}_cap3_${size_range}_blastn_vs_viral_db.bls \
        -evalue ${params.blastn_evalue} \
        -num_threads ${task.cpus} \
        -outfmt '6 qseqid sgi sacc length pident mismatch gapopen qstart qend qlen sstart send slen sstrand evalue bitscore qcovhsp stitle staxids qseq sseq sseqid qcovs qframe sframe' \
        -max_target_seqs 50

    #2. megablast search
    blastn -query ${sampleid}_cap3_${size_range}.fasta \
        -db ${blast_viral_db_dir}/${blast_viral_db_name} \
        -out ${sampleid}_cap3_${size_range}_megablast_vs_viral_db.bls \
        -evalue ${params.blastn_evalue} \
        -num_threads ${task.cpus} \
        -outfmt '6 qseqid sgi sacc length pident mismatch gapopen qstart qend qlen sstart send slen sstrand evalue bitscore qcovhsp stitle staxids qseq sseq sseqid qcovs qframe sframe' \
        -max_target_seqs 50
    """
}

process FILTER_BLASTN_VIRAL_DB_CAP3 {
    publishDir "${params.outdir}/01_VirReport/${sampleid}/blastn/viral_db", mode: 'link', overwrite: true, pattern: "*{.txt}"
    tag "$sampleid"

    input:
    tuple val(sampleid), \
        file(fastqfile), \
        file(fastq_filt_by_size), \
        file("${sampleid}_cap3_${size_range}.fasta"), \
        file("${sampleid}_cap3_${size_range}_blastn_vs_viral_db.bls"), \
        file("${sampleid}_cap3_${size_range}_megablast_vs_viral_db.bls")

    output:
    file "summary_${sampleid}_cap3_${size_range}_*_vs_viral_db.bls_viruses_viroids*.txt"
    file "summary_${sampleid}_cap3_${size_range}_*_vs_viral_db.bls_filtered.txt"

    tuple val(sampleid),
          file(fastqfile),
          file(fastq_filt_by_size),
          file("summary_${sampleid}_cap3_${size_range}_megablast_vs_viral_db.bls_viruses_viroids.txt"),
          emit: viral_db_blast_results
    
    script:
    """
    c1grep() { grep "\$@" || test \$? = 1; }
    #retain 1st blast hit
    for var in ${sampleid}_cap3_${size_range}_megablast_vs_viral_db.bls ${sampleid}_cap3_${size_range}_blastn_vs_viral_db.bls;
        do 
            cat \${var} | awk '{print \$1}' | sort | uniq > \${var}.top1.ids
            for i in `cat \${var}.top1.ids`; do echo "fetching top hits..." \$i; grep \$i \${var} | head -1 >> \${var}.top1Hits.txt ; done
            cat \${var}.top1Hits.txt | sed 's/ /_/g' > \${var}.txt

            #summarise the blast files
            java -jar ${projectDir}/bin/BlastTools.jar -t blastn \${var}.txt

            sequence_length.py --virus_list summary_\${var}.txt --contig_fasta ${sampleid}_cap3_${size_range}.fasta --out summary_\${var}_with_contig_lengths.txt

            #only retain hits to plant viruses
            c1grep  "virus\\|viroid\\|Endogenous" summary_\${var}_with_contig_lengths.txt > summary_\${var}_filtered.txt

            sed -i 's/Elephantopus_scaber_closterovirus/Citrus_tristeza_virus/'  summary_\${var}_filtered.txt
            sed -i 's/Hop_stunt_viroid_-_cucumber/Hop_stunt_viroid/' summary_\${var}_filtered.txt
            
            if [[ ! -s summary_\${var}_filtered.txt ]]
            then
                echo -e "Species\tsacc\tnaccs\tlength\tslen\tcov\tav-pident\tstitle\tqseqids\tcontig_ind_lengths\tcumulative_contig_len\tcontig_lenth_min\tcontig_lenth_max" > summary_\${var}_viruses_viroids.txt;
                exit 0
            else
                #fetch unique virus/viroid species name from Blast summary reports
                cat summary_\${var}_filtered.txt | awk '{print \$7}' | awk -F "|" '{print \$2}'| sort | uniq | sed 's/Species://' > \${var}_uniq.ids

                #retrieve the best hit for each unique virus/viroid species name by selecting longest alignment (column 3) and highest genome coverage (column 5)
                touch \${var}_filtered.txt
                for id in `cat \${var}_uniq.ids`;
                    do
                        grep \${id} summary_\${var}_filtered.txt | sort -k3,3nr -k5,5nr | head -1 >> \${var}_filtered.txt
                    done

                #print the header of the inital summary_blastn file
                cat summary_\${var}_with_contig_lengths.txt | head -1 > header

                #report 1
                cat header \${var}_filtered.txt > summary_\${var}_viruses_viroids.txt
                
                #fetch genus names of identified hits
                awk '{print \$7}' summary_\${var}_viruses_viroids.txt | awk -F "|" '{print \$2}' | sed 's/Species://' | sed 1d > wanted.names
            
                #add species to report
                paste wanted.names \${var}_filtered.txt | sort |  awk '\$4>=40' > summary_\${var}_viruses_viroids.tmp.txt

                #report 2
                awk '{print "Species" "\\t" \$0 }' header > header2
                cat header2 summary_\${var}_viruses_viroids.tmp.txt | awk -F"\\t" '\$1!=""&&\$2!=""&&\$3!=""' > summary_\${var}_viruses_viroids.txt

            fi
        done
    """
}

process COVSTATS_VIRAL_DB {
    tag "$sampleid"
    label "setting_6"
    publishDir "${params.outdir}/01_VirReport/${sampleid}/alignments/viral_db", mode: 'link', overwrite: true, pattern: "*{.fa*,.fasta,metrics.txt,scores.txt,targets.txt,stats.txt,log.txt,.bcf*,.vcf.gz*,.bam*}"
    containerOptions "${bindOptions}"
    
    input:
    tuple val(sampleid), path(fastqfile), path(fastq_filt_by_size), path(samplefile)
    output:
    path("${sampleid}_${size_range}*")
    path("${sampleid}_${size_range}_top_scoring_targets_with_cov_stats_viral_db.txt"), emit: viral_db_detections_summary
    
    script:
    """
    filter_and_derive_stats.py --sample ${sampleid} --rawfastq ${fastqfile} --fastqfiltbysize  ${fastq_filt_by_size} --results ${samplefile} --read_size ${size_range} --blastdbpath ${blast_viral_db_dir}/${blast_viral_db_name} --dedup ${params.dedup} --mode viral_db --cpu ${task.cpus}
    """
}

process DETECTION_REPORT_VIRAL_DB {
    label "local"
    publishDir "${params.outdir}/01_VirReport/Summary", mode: 'link', overwrite: true
    containerOptions "${bindOptions}"

    input:
    file ('*')

    output:
    path("VirReport_detection_summary*viral_db*.txt")

    script:
    """
    if ${params.sampleinfo}; then
        detection_report.py --read_size ${size_range} --threshold ${params.contamination_flag} --viral_db true --diagno ${params.diagno} --dedup ${params.dedup} --sampleinfo ${params.sampleinfo_path}
    else
        detection_report.py --read_size ${size_range} --threshold ${params.contamination_flag} --viral_db true --diagno ${params.diagno} --dedup ${params.dedup}
    fi
    """
}

process TBLASTN_VIRAL_DB {
    label "setting_4"
    publishDir "${params.outdir}/01_VirReport/${sampleid}/tblastn/viral_db", mode: 'link', overwrite: true
    tag "$sampleid"
    containerOptions "${bindOptions}"

    input:
    tuple val(sampleid), file(cap3_fasta)
    
    output:
    path("${sampleid}_cap3_${size_range}_getorf.all.fasta")
    path("${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_out.bls")
    path("${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits_virus_viroids_final.txt")

    script:
    """
    getorf -sequence ${cap3_fasta} -outseq ${sampleid}_cap3_${size_range}_getorf.fasta  -minsize ${params.orf_minsize}
    getorf -sequence ${cap3_fasta} -circular True -outseq ${sampleid}_cap3_${size_range}_getorf.circular.fasta -minsize ${params.orf_circ_minsize}
    cat ${sampleid}_cap3_${size_range}_getorf.fasta ${sampleid}_cap3_${size_range}_getorf.circular.fasta >  ${sampleid}_cap3_${size_range}_getorf.all.fasta
    #cat ${sampleid}_cap3_${size_range}_getorf.all.fasta | grep ">" | sed 's/>//' | awk '{print \$1}' > ${sampleid}_cap3_${size_range}_getorf.all.fasta.ids

    tblastn -query ${sampleid}_cap3_${size_range}_getorf.all.fasta \
        -db ${blast_viral_db_dir}/${blast_viral_db_name} \
        -evalue ${params.tblastn_evalue} \
        -out ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_out.bls \
        -num_threads ${task.cpus} \
        -max_target_seqs 10 \
        -outfmt '6 qseqid sseqid pident nident length mismatch gapopen gaps qstart qend qlen qframe sstart send slen evalue bitscore qcovhsp sallseqid stitle'
    
    grep ">" ${sampleid}_cap3_${size_range}_getorf.all.fasta | sed 's/>//' | cut -f1 -d ' ' | sort | uniq > ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_out.wanted.ids
    for i in `cat ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_out.wanted.ids`; do
        grep \$i ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_out.bls | head -n5 >> ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits.txt;
    done

    grep -i "Virus" ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits.txt > ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits_virus_viroids.txt  || [[ \$? == 1 ]]
    grep -i "Viroid" ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits.txt >> ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits_virus_viroids.txt || [[ \$? == 1 ]]
    
    #modify accordingly depending on version of viral_db
    cut -f2 ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits_virus_viroids.txt | cut -f2 -d '|' > seq_ids.txt
    cut -f20 ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits_virus_viroids.txt | cut -f2 -d '|'  | sed 's/Species://' > species_name_extraction.txt
    paste seq_ids.txt ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits_virus_viroids.txt  species_name_extraction.txt > ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits_virus_viroids_mod.txt
    awk -v OFS='\\t' '{ print \$1,\$2,\$4,\$5,\$6,\$7,\$8,\$9,\$10,\$11,\$12,\$13,\$14,\$15,\$16,\$17,\$18,\$19,\$20,\$22}'  ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits_virus_viroids_mod.txt | sed 's/ /_/g' > ${sampleid}_cap3_${size_range}_getorf.all_tblastn_vs_viral_db_top5Hits_virus_viroids_final.txt
    """
}

process BLASTN_NT_CAP3 {
    label "setting_2"
    publishDir "${params.outdir}/01_VirReport/${sampleid}/blastn/NT", mode: 'link', overwrite: true, pattern: "*{vs_NT.bls,_top5Hits.txt,_final.txt,taxonomy.txt}"
    tag "$sampleid"
    containerOptions "${bindOptions}"

    input:
    tuple val(sampleid), file(fastqfile), file(fastq_filt_by_size), file(cap3_fasta)

    output:
    path("${cap3_fasta.baseName}_blastn_vs_NT.bls")
    path("${cap3_fasta.baseName}_blastn_vs_NT_top5Hits.txt")
    path("${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids.txt")
    path("summary_${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids_final.txt")
    path("summary_${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids.txt")

    tuple val(sampleid),
          file(fastqfile),
          file(fastq_filt_by_size),
          file("summary_${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids_final.txt"),
          file("${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids_seq_ids_taxonomy.txt"),
          emit: viral_ncbi_blast_results
    
    tuple val(sampleid),
          file(cap3_fasta),
          file("${cap3_fasta.baseName}_blastn_vs_NT_top5Hits.txt"),
          emit: viral_ncbi_blast_results_for_blastx

    script:
    def blast_task_param = (params.blastn_method == "blastn") ? "-task blastn" : ''
    """
    #To extract the taxonomy, copy the taxonomy databases associated with your blast NT database
    if [[ ! -f ${params.blast_db_dir}/taxdb.btd || ! -f ${params.blast_db_dir}/taxdb.bti ]]; then
        update_blastdb.pl taxdb
        tar -xzf taxdb.tar.gz
    else
        cp ${params.blast_db_dir}/taxdb.btd .
        cp ${params.blast_db_dir}/taxdb.bti .
    fi

    blastn ${blast_task_param} \
        -query ${cap3_fasta} \
        -db ${blastn_db_name} \
        -negative_seqidlist ${params.negative_seqid_list} \
        -out ${cap3_fasta.baseName}_blastn_vs_NT.bls \
        -evalue ${params.blastn_evalue} \
        -num_threads ${task.cpus} \
        -outfmt '6 qseqid sgi sacc length pident mismatch gapopen qstart qend qlen sstart send slen sstrand evalue bitscore qcovhsp stitle staxids qseq sseq sseqid qcovs qframe sframe sscinames' \
        -max_target_seqs 50 \
        -word_size 24

    grep ">" ${cap3_fasta.baseName}.fasta | sed 's/>//' > ${cap3_fasta.baseName}.ids
    
    #fetch top blastn hits
    for i in `cat ${cap3_fasta.baseName}.ids`; do
        grep \$i ${cap3_fasta.baseName}_blastn_vs_NT.bls | head -n5 >> ${cap3_fasta.baseName}_blastn_vs_NT_top5Hits.txt;
    done
    
    grep -i "Virus" ${cap3_fasta.baseName}_blastn_vs_NT_top5Hits.txt > ${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids_tmp.txt  || [[ \$? == 1 ]]
    grep -i "Viroid" ${cap3_fasta.baseName}_blastn_vs_NT_top5Hits.txt >> ${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids_tmp.txt || [[ \$? == 1 ]]
    cat ${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids_tmp.txt | sed 's/ /_/g' > ${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids.txt
    cut -f3,26 ${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids.txt | sort | uniq > ${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids_seq_ids_taxonomy.txt
    
    java -jar ${projectDir}/bin/BlastTools.jar -t blastn ${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids.txt

    rm taxdb.btd
    rm taxdb.bti
    
    sequence_length.py --virus_list summary_${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids.txt --contig_fasta ${cap3_fasta.baseName}.fasta --out summary_${cap3_fasta.baseName}_blastn_vs_NT_top5Hits_virus_viroids_final.txt
    """
}

process COVSTATS_NT {
    tag "$sampleid"
    label "setting_6"
    publishDir "${params.outdir}/01_VirReport/${sampleid}/alignments/NT", mode: 'link', overwrite: true, pattern: "*{.fa*,.fasta,metrics.txt,scores.txt,targets.txt,stats.txt,log.txt,.bcf*,.vcf.gz*,.bam*}"
    containerOptions "${bindOptions}"
    
    input:
    tuple val(sampleid), file(fastqfile), file(fastq_filt_by_size), file(samplefile), file(taxonomy)

    output:
    path("${sampleid}_${size_range}*")
    path("${sampleid}_${size_range}_top_scoring_targets_*with_cov_stats.txt"), emit: viral_ncbi_detections_summary
    
    script:
    """
    filter_and_derive_stats.py --sample ${sampleid} --rawfastq ${fastqfile} --fastqfiltbysize  ${fastq_filt_by_size} --results ${samplefile} --read_size ${size_range} --taxonomy ${taxonomy} --blastdbpath ${blastn_db_name} --dedup ${params.dedup} --cpu ${task.cpus} --mode ncbi
    
    """
}

process DETECTION_REPORT_NT {
    label "local"
    publishDir "${params.outdir}/01_VirReport/Summary", mode: 'link', overwrite: true
    containerOptions "${bindOptions}"

    input:
    path('*')

    output:
    file "VirReport_detection_summary*.txt"

    script:
    """
    if [[ ${params.sampleinfo} == true ]]; then
        detection_report.py --read_size ${size_range} --threshold ${params.contamination_flag} --dedup ${params.dedup} --diagno ${params.diagno} --targets ${params.targets_file} --sampleinfopath ${params.sampleinfo_path}
    else
        detection_report.py --read_size ${size_range} --threshold ${params.contamination_flag} --dedup ${params.dedup} --diagno ${params.diagno} --targets ${params.targets_file}
    fi
    """
}

//blastx jobs runs out of memory if only given 64Gb
process BLASTX {
    label "setting_2"
    publishDir "${params.outdir}/01_VirReport/${sampleid}/blastx/NT", mode: 'link', overwrite: true
    tag "$sampleid"
    containerOptions "${bindOptions}"

    input:
    tuple val(sampleid), file(cap3_fasta), file(top5Hits)
    
    output:
    file "${cap3_fasta.baseName}_blastx_vs_NT.bls"
    file "${cap3_fasta.baseName}_blastx_vs_NT_topHits.txt"
    file "${cap3_fasta.baseName}_blastx_vs_NT_topHits_virus_viroids_final.txt"
    file "summary_${cap3_fasta.baseName}_blastx_vs_NT_topHits_virus_viroids_final.txt"
    
    script:
    """
    #To extract the taxonomy, copy the taxonomy databases associated with your blast NT database
    if [[ ! -f ${params.blast_db_dir}/taxdb.btd || ! -f ${params.blast_db_dir}/taxdb.bti ]]; then
        perl ${projectDir}/bin/update_blastdb.pl taxdb
        tar -xzf taxdb.tar.gz
    else
        cp ${params.blast_db_dir}/taxdb.btd .
        cp ${params.blast_db_dir}/taxdb.bti .
    fi
    #extract contigs with blastn results
    cut -f1 ${top5Hits} | sort | uniq > denovo_contig_name_ids_with_blastn_hits.txt

    #extract all contigs names from de novo assembly
    grep ">" ${cap3_fasta.baseName}.fasta | sed 's/>//' | sort | uniq > denovo_contig_name_ids.txt

    #extract contigs with no blastn results
    grep -v -F -f denovo_contig_name_ids_with_blastn_hits.txt denovo_contig_name_ids.txt | sort  > denovo_contig_name_ids_unassigned.txt || [[ \$? == 1 ]]
    
    perl ${projectDir}/bin/faSomeRecords.pl -f ${cap3_fasta.baseName}.fasta -l denovo_contig_name_ids_unassigned.txt -o ${cap3_fasta.baseName}_no_blastn_hits.fasta

    extract_seqs_rename.py ${cap3_fasta.baseName}_no_blastn_hits.fasta ${params.blastx_len} \
                            | sed "s/CONTIG/${sampleid}_${params.minlen}-${params.maxlen}_/" \
                            > ${cap3_fasta.baseName}_no_blastn_hits_${params.blastx_len}nt.fasta

    blastx -query ${cap3_fasta.baseName}_no_blastn_hits_${params.blastx_len}nt.fasta \
        -db ${blastp_db_name} \
        -out ${cap3_fasta.baseName}_blastx_vs_NT.bls \
        -evalue ${params.blastx_evalue} \
        -num_threads ${task.cpus} \
        -outfmt '6 qseqid sseqid pident nident length mismatch gapopen gaps qstart qend qlen qframe sstart send slen evalue bitscore qcovhsp sallseqid sscinames' \
        -max_target_seqs 1

    #grep ">" ${cap3_fasta} | sed 's/>//' > ${cap3_fasta.baseName}.ids
    cut -f1 ${cap3_fasta.baseName}_blastx_vs_NT.bls  | sed 's/ //' | sort | uniq > ${cap3_fasta.baseName}.ids
    
    #fetch top blastn hits
    touch  ${cap3_fasta.baseName}_blastx_vs_NT_topHits.txt
    for i in `cat ${cap3_fasta.baseName}.ids`; do
        grep \$i ${cap3_fasta.baseName}_blastx_vs_NT.bls | head -n1 >> ${cap3_fasta.baseName}_blastx_vs_NT_topHits.txt;
    done
    grep -i "Virus" ${cap3_fasta.baseName}_blastx_vs_NT_topHits.txt > ${cap3_fasta.baseName}_blastx_vs_NT_topHits_virus_viroids.txt  || [[ \$? == 1 ]]
    grep -i "Viroid" ${cap3_fasta.baseName}_blastx_vs_NT_topHits.txt >> ${cap3_fasta.baseName}_blastx_vs_NT_topHits_virus_viroids.txt  || [[ \$? == 1 ]]
    sed 's/ /_/g' ${cap3_fasta.baseName}_blastx_vs_NT_topHits_virus_viroids.txt  |  awk -v OFS='\\t' '{ print \$2,\$1,\$3,\$4,\$5,\$6,\$7,\$8,\$9,\$10,\$11,\$12,\$13,\$14,\$15,\$16,\$17,\$18,\$19,\$20}' > ${cap3_fasta.baseName}_blastx_vs_NT_topHits_virus_viroids_final.txt
    
    java -jar ${projectDir}/bin/BlastTools.jar -t blastp ${cap3_fasta.baseName}_blastx_vs_NT_topHits_virus_viroids_final.txt
    rm taxdb.btd
    rm taxdb.bti
    """
}

process VIRUS_DETECT {
    tag "$sampleid"
    label "setting_6"
    containerOptions "${bindOptions}"

    input:
    tuple val(sampleid), file(fastqfile), file(fastq_filt_by_size)

    output:
    tuple val(sampleid),
        path(fastq_filt_by_size),
        path("${sampleid}_${size_range}.combined"),
        emit: virusdetect

    script:
    """
    virus_detect.pl --thread_num ${task.cpus}  \
                    --reference ${params.virusdetect_db_path} \
                    ${fastq_filt_by_size} \
                    --depth_cutoff ${params.virus_depth_cutoff}

    cp ${sampleid}_${size_range}_temp/${sampleid}_${size_range}.combined .
    """
}

process VIRUS_IDENTIFY {
    publishDir "${params.outdir}/02_VirusDetect", mode: 'link', overwrite: true, pattern: "*/*{references,combined,fa,html,sam,txt,identified,identified_with_depth}"
    tag "$sampleid"
    label "setting_4"
    containerOptions "${bindOptions}"

    input:
    tuple val(sampleid),
        file(samplefile),
        file("${sampleid}_${size_range}.combined")

    output:
    path "${sampleid}/*"
    path("${sampleid}_${size_range}.blastn.summary.filtered.txt"), emit: virusdetectblastnsummaryfiltered_flag
    path("${sampleid}_${size_range}.blastn.summary.spp.txt"), emit: virusdetectblastnsummary_flag

    script:
    """
    virus_identify.pl --reference ${params.virusdetect_db_path} \
                        --word-size 11 \
                        --exp-value 1e-05 \
                        --exp-valuex 0.01 \
                        --percent-identity 25 \
                        --cpu-num ${task.cpus}  \
                        --mis-penalty -3 \
                        --gap-cost -1 \
                        --gap-extension -1 \
                        --hsp-cover 0.75 \
                        --diff-ratio 0.25 \
                        --diff-contig-cover 0.5 \
                        --diff-contig-length 100 \
                        --coverage-cutoff 0.1 \
                        --depth-cutoff ${params.virus_depth_cutoff} \
                        --siRNA-percent 0.5 \
                        --novel-len-cutoff 100 \
                        --debug \
                        ${samplefile} \
                        ${sampleid}_${size_range}.combined

    mv result_${sampleid}_${size_range} ${sampleid}
    mv ${sampleid}_${size_range}.combined ${sampleid}

    #if VirusDetect does not detect a virus hit via blastn, no summary files will be created
    #Exit process
    if [[ ! -f ${sampleid}/${sampleid}_${size_range}.blastn.summary.txt ]]; then
        touch ${sampleid}/${sampleid}_${size_range}.blastn.summary.txt
        echo -e "Sample\tReference\tLength\t%Coverage\t#contig\tDepth\tDepth_Norm\t%Identity\t%Identity_max\t%Identity_min\tGenus\tDescription\tSpecies" | tee ${sampleid}_${size_range}.blastn.summary.filtered.txt >  ${sampleid}/${sampleid}_${size_range}.blastn.summary.filtered.txt
        echo -e "Sample\tReference\tLength\t%Coverage\t#contig\tDepth\tDepth_Norm\t%Identity\t%Identity_max\t%Identity_min\tGenus\tDescription\tSpecies" | tee ${sampleid}_${size_range}.blastn.summary.spp.txt > ${sampleid}/${sampleid}_${size_range}.blastn.summary.spp.txt 
        exit 0
    else
        cp ${sampleid}/${sampleid}_${size_range}.blastn.summary.txt .
    fi

    cut -f2 ${sampleid}_${size_range}.blastn.summary.txt | grep -v Reference > ${sampleid}_${size_range}.blastn_ids.txt
    cp ${params.blast_db_dir}/taxdb.btd .
    cp ${params.blast_db_dir}/taxdb.bti .

    touch ${sampleid}_${size_range}.blastn_spp.txt

    for id in `cat ${sampleid}_${size_range}.blastn_ids.txt`;
        do 
            blastdbcmd -db ${blastn_db_name} -entry \${id} -outfmt '%L' | uniq | sed 's/ /_/g' >>  ${sampleid}_${size_range}.blastn_spp.txt
        done
    sed -i '1 i\\Species' ${sampleid}_${size_range}.blastn_spp.txt
    paste ${sampleid}_${size_range}.blastn.summary.txt ${sampleid}_${size_range}.blastn_spp.txt  > ${sampleid}_${size_range}.blastn.summary.spp.txt
    
    #fetch unique virus/viroid species name from Blast summary reports
    cat ${sampleid}_${size_range}.blastn_spp.txt | grep -v Species | sort | uniq  > ${sampleid}_${size_range}.blastn_unique_spp.txt

    head -n1 ${sampleid}_${size_range}.blastn.summary.spp.txt > ${sampleid}_${size_range}.blastn.summary.tmp.txt
    
    for id in `cat ${sampleid}_${size_range}.blastn_unique_spp.txt`;
        do
            grep \${id} ${sampleid}_${size_range}.blastn.summary.spp.txt | sort -k4,4nr | head -1 >> ${sampleid}_${size_range}.blastn.summary.tmp.txt
        done

    grep -v retrovirus ${sampleid}_${size_range}.blastn.summary.tmp.txt > ${sampleid}_${size_range}.blastn.summary.filtered.txt
    for i in ${sampleid}_${size_range}.blastn.summary.spp.txt ${sampleid}_${size_range}.blastn.summary.filtered.txt;
        do
            sed -i 's/Coverage (%)/%Coverage/' \${i}
            sed -i 's/Depth (Norm)/Depth_Norm/' \${i}
            sed -i 's/Iden Max/Identity_max/' \${i}
            sed -i 's/Iden Min/Identity_min/' \${i}
        done


    rm taxdb.btd
    rm taxdb.bti
    cp ${sampleid}_${size_range}.blastn.summary.spp.txt ${sampleid}/${sampleid}_${size_range}.blastn.summary.spp.txt
    cp ${sampleid}_${size_range}.blastn.summary.filtered.txt ${sampleid}/${sampleid}_${size_range}.blastn.summary.filtered.txt
    """
}

process VIRUS_DETECT_BLASTN_SUMMARY {
    publishDir "${params.outdir}/02_VirusDetect/Summary", mode: 'link', overwrite: true
    label "local"

    input:
    path("*blastn.summary.spp.txt")
    path("*blastn.summary.filtered.txt")

    output:
    path("run_summary_top_scoring_targets_virusdetect_${size_range}*.txt")
    path("run_summary_top_scoring_targets_virusdetect_filtered_${size_range}*.txt")

    script:
    """
    summary_virus_detect.py --read_size ${size_range}
    """
}

process SYNTHETIC_OLIGOS {
    tag "$sampleid"
    label "setting_6"
    publishDir "${params.outdir}/00_quality_filtering/${sampleid}/synthetic_oligos", mode: 'link', overwrite: true
    
    input:
    tuple val(sampleid), file(fastqfile), file(fastq_filt_by_size)

    output:
    file("${sampleid}_${size_range}_synthetic_oligos_stats.txt")
    path("${sampleid}_${size_range}_synthetic_oligos_stats.txt"), emit: synthetic_oligo_results

    script:
    """
    synthetic_oligos.py --sample ${sampleid} --rawfastq ${fastqfile} --fastqfiltbysize ${fastq_filt_by_size} --read_size ${size_range}
    """
}

process SYNTHETIC_OLIGO_SUMMARY {
    publishDir "${params.outdir}/00_quality_filtering/qc_report", mode: 'link'
    containerOptions "${bindOptions}"

    input:
    path("*synthetic_oligos_stats.txt")

    output:
    file "synthetic_oligo_summary*.txt"
    
    script:
    """
    if [[ ${params.sampleinfo} == true ]]; then
        synthetic_oligos_summary.py --sampleinfopath ${params.sampleinfo_path}
    else
        synthetic_oligos_summary.py
    fi
    """
}

workflow {
  if (params.indexfile) {
    Channel
        .fromPath(params.indexfile, checkIfExists: true)
        .splitCsv(header:true)
        .map{ row-> tuple(row.sampleid), file(row.samplepath) }
        .groupTuple()
        .set{ samples_ch }
    Channel
        .fromPath(params.indexfile, checkIfExists: true)
        .splitCsv(header:true)
        .map{ row-> tuple(row.sampleid), file(row.samplepath) }
        .set{ read_size_selection_ch }
  } else { exit 1, "Input samplesheet file not specified!" }

  if (params.qualityfilter) {
    FASTQC_RAW(samples_ch) 
    MERGE_LANES(samples_ch)
    ADAPTER_TRIMMING(MERGE_LANES.out.merged)
    QUAL_TRIMMING_AND_QC(ADAPTER_TRIMMING.out.adapter_trimmed)
    if (params.rna_source_profile) {
      RNA_SOURCE_PROFILE(ADAPTER_TRIMMING.out.adapter_trimmed)
      RNA_SOURCE_PROFILE_REPORT(RNA_SOURCE_PROFILE.out.rna_source_bowtie_results.collect().ifEmpty([]))
      }
    DERIVE_USABLE_READS(QUAL_TRIMMING_AND_QC.out.qual_trimmed)
    if (params.synthetic_oligos) {
      SYNTHETIC_OLIGOS(DERIVE_USABLE_READS.out.usable_reads)
      SYNTHETIC_OLIGO_SUMMARY(SYNTHETIC_OLIGOS.out.synthetic_oligo_results.collect().ifEmpty([]))
    }
    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(QUAL_TRIMMING_AND_QC.out.cutadapt_qual_filt_results.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(QUAL_TRIMMING_AND_QC.out.fastp_results.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(QUAL_TRIMMING_AND_QC.out.read_length_dist_results.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(DERIVE_USABLE_READS.out.cutadapt_18_25nt_results.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(DERIVE_USABLE_READS.out.cutadapt_21_22nt_results.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(DERIVE_USABLE_READS.out.cutadapt_24nt_results.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(DERIVE_USABLE_READS.out.bowtie_usable_read_results.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(ADAPTER_TRIMMING.out.umi_tools_results.collect().ifEmpty([]))
    //ch_multiqc_files.view()
    
    QCREPORT(ch_multiqc_files.collect())
    //QCREPORT(QUAL_TRIMMING_AND_QC.out.cutadapt_qual_filt_results.collect().ifEmpty([]),
    //  QUAL_TRIMMING_AND_QC.out.fastp_results.collect().ifEmpty([]),
    //  QUAL_TRIMMING_AND_QC.out.read_length_dist_results.collect().ifEmpty([]),
    //  DERIVE_USABLE_READS.out.cutadapt_18_25nt_results.collect().ifEmpty([]),
    //  DERIVE_USABLE_READS.out.cutadapt_21_22nt_results.collect().ifEmpty([]),
    //  DERIVE_USABLE_READS.out.cutadapt_24nt_results.collect().ifEmpty([]),
    //  DERIVE_USABLE_READS.out.bowtie_usable_read_results.collect().ifEmpty([]),
    //  ADAPTER_TRIMMING.out.umi_tools_results.collect().ifEmpty([]))
    DENOVO_ASSEMBLY(DERIVE_USABLE_READS.out.usable_reads)
    } else {
    // If user does not specify qualityfilter parameter, then only read size selection (using the minlen and maxlen params specified in the nextflow.config file) will be performed on the fastq file specified in the index file
    READPROCESSING(read_size_selection_ch)
    DENOVO_ASSEMBLY(READPROCESSING.out.fastq)
    }

  if (params.virreport_viral_db) {
    BLASTN_VIRAL_DB_CAP3(DENOVO_ASSEMBLY.out.assembly_for_blastn)
    FILTER_BLASTN_VIRAL_DB_CAP3(BLASTN_VIRAL_DB_CAP3.out.blast_results)
    COVSTATS_VIRAL_DB(FILTER_BLASTN_VIRAL_DB_CAP3.out.viral_db_blast_results)
    if (params.detection_reporting_viral_db) {
      DETECTION_REPORT_VIRAL_DB(COVSTATS_VIRAL_DB.out.viral_db_detections_summary.collect().ifEmpty([]))
    }
    TBLASTN_VIRAL_DB(DENOVO_ASSEMBLY.out.assembly_for_tblastn)
  }
  if (params.virreport_ncbi) {
    BLASTN_NT_CAP3(DENOVO_ASSEMBLY.out.assembly_for_blastn)
    COVSTATS_NT(BLASTN_NT_CAP3.out.viral_ncbi_blast_results)
    if (params.detection_reporting_nt) {
      DETECTION_REPORT_NT(COVSTATS_NT.out.viral_ncbi_detections_summary.collect().ifEmpty([]))
    }
    if (params.blastx) {
      BLASTX(BLASTN_NT_CAP3.out.viral_ncbi_blast_results_for_blastx)
    }
  }
  if (params.virusdetect) {
    if (params.qualityfilter) {
      VIRUS_DETECT(DERIVE_USABLE_READS.out.usable_reads)
    }
    else {
      VIRUS_DETECT(READPROCESSING.out.fastq)
    }
    VIRUS_IDENTIFY(VIRUS_DETECT.out.virusdetect)
    VIRUS_DETECT_BLASTN_SUMMARY(VIRUS_IDENTIFY.out.virusdetectblastnsummary_flag.collect().ifEmpty([]),
                                VIRUS_IDENTIFY.out.virusdetectblastnsummaryfiltered_flag.collect().ifEmpty([]))
  }
}

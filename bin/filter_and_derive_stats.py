#!/usr/bin/env python
import argparse
import pandas as pd
import numpy as np
import os
import subprocess
from functools import reduce
import glob

def main():
    ################################################################################
    parser = argparse.ArgumentParser(description="Load blast results")

    # All the required arguments #
    parser.add_argument("--results", type=str)
    parser.add_argument("--rawfastq", type=str)
    parser.add_argument("--fastqfiltbysize", type=str)
    parser.add_argument("--sample", type=str)
    parser.add_argument("--cov", help="derive coverage stats",
                        action="store_true")
    parser.add_argument("--read_size", type=str)
    parser.add_argument("--taxonomy", type=str)
    parser.add_argument("--blastdbpath", type=str)
    parser.add_argument("--targets", help="extract specific targets specified in file provided in targetspath", 
                        action="store_true")
    parser.add_argument("--targetspath", type=str)              
    args = parser.parse_args()
    
    results_path = args.results
    sample = args.sample
    coverage_cal = args.cov
    rawfastq = args.rawfastq
    fastqfiltbysize = args.fastqfiltbysize
    read_size = args.read_size
    taxonomy = args.taxonomy
    blastdbpath = args.blastdbpath
    targets = args.targets
    targetspath = args.targetspath

    raw_data = pd.read_csv(results_path, header=0, sep="\t",index_col=None)

    #load list of target viruses and viroids and matching official ICTV name
    taxonomy_df = pd.read_csv(taxonomy, header=0, sep="\t")
    taxonomy_df.columns =["sacc", "Targetted_sp_generic_name"]
    #print(taxonomy_df)

    if len(raw_data) == 0:
        print("DataFrame is empty!")
        csv_file1 = open(sample + "_" + read_size + "_all_targets_with_scores.txt", "w")
        csv_file1.write("sacc\tnaccs\tlength\tslen\tcov\tav-pident\tstitle\tqseqids\tRNA_type\tTargetted_sp_generic_name\tnaccs_score\tlength_score\tavpid_score\tcov_score\tgenome_score\tcompleteness_score\ttotal_score")
        csv_file1.close()
        csv_file2 = open(sample + "_" + read_size + "_top_scoring_targets.txt", "w")
        csv_file2.write("sacc\tnaccs\tlength\tslen\tcov\tav-pident\tstitle\tqseqids\tTargetted_sp_generic_name\tRNA_type\tTargetted_sp_generic_name\tnaccs_score\tlength_score\tavpid_score\tcov_score\tgenome_score\tcompleteness_score\ttotal_score")       
        csv_file2.close()
        csv_file3 = open(sample + "_" + read_size + "_top_scoring_targets_with_cov_stats.txt", "w")
        csv_file3.write("Sample\tsacc\tnaccs\tlength\tslen\tcov\tav-pident\tstitle\tqseqids\tTargetted_sp_generic_name\tnaccs_score\tlength_score\tavpid_score\tcov_score\tgenome_score\tcompleteness_score\ttotal_score\tMean coverage\tRead count\tRead count norm\tRead count norm\tPCT_1X\tPCT_10X\tPCT_20X")
        csv_file3.close()
        exit ()

    #print(raw_data).head(10)
    print("Cleaning up the data")
    print("Remove double spacing")
    raw_data = raw_data.replace("\s+", " ", regex=True)

    print("Remove hyphens")
    raw_data["stitle"] = raw_data["stitle"].str.replace("-", " ")

    print("Remove underscores")
    raw_data["stitle"] = raw_data["stitle"].str.replace("_"," ")

    print("Remove commas")
    raw_data["stitle"] = raw_data["stitle"].str.replace(","," ")

    print("Remove problematic text in virus description names")
    #this fixes virus names like "Prunus_necrotic_ringspot_virus_Acot_genomic_RNA,_segment_RNA2,_complete_sequence"
    raw_data["stitle"] = raw_data["stitle"].str.replace(" genomic RNA segment","segment")
    
    raw_data["stitle"] = raw_data["stitle"].str.replace("{complete viroid sequence}","", regex=False)
    #This is a complete genome
    raw_data["stitle"] =  raw_data["stitle"].str.replace("Rubus yellow net virus isolate Canadian 2 hypothetical protein genes  partial cds; hypothetical proteins  polyprotein  ORF 6  and hypothetical protein genes  complete cds; and hypothetical protein genes  partial cds","Rubus yellow net virus isolate Canadian 2 complete cds")
    #remove resistance genes from list of results
    raw_data = raw_data[~raw_data["stitle"].str.contains("resistance gene")]
   
    raw_data = pd.merge(raw_data, taxonomy_df, on=["sacc"])
    raw_data["Targetted_sp_generic_name"] = raw_data["Targetted_sp_generic_name"].str.replace("_", " ")

    raw_data = raw_data.sort_values("stitle")

    #This step will only extract viruses and viroids of interest
    if targets:
        colname = ["Targetted_sp_generic_name"]
        targets_df = pd.read_csv(targetspath, names=colname, header=None, sep="\t", index_col=None)
        raw_data = pd.merge(raw_data, targets_df, on=["Targetted_sp_generic_name"])

    print("If present in original nomenclature, add RNA type information to virus standardised species name")

    raw_data["RNA_type"] = np.where(raw_data.stitle.str.contains("RNA1|RNA 1|segment 1"), "RNA1",
                           np.where(raw_data.stitle.str.contains("RNA2|RNA 2|segment 2"), "RNA2",
                           np.where(raw_data.stitle.str.contains("RNA3|RNA 3|segment 3"), "RNA3", "NaN")))
    
    raw_data["Targetted_sp_generic_name_updated"] = raw_data[["Targetted_sp_generic_name", "RNA_type"]].agg(" ".join, axis=1)
    raw_data["Targetted_sp_generic_name_updated"] = raw_data["Targetted_sp_generic_name_updated"].astype(str).str.strip("NaN")
    raw_data["Targetted_sp_generic_name_updated"] = raw_data["Targetted_sp_generic_name_updated"].astype(str).str.rstrip( )
 
    raw_data = raw_data.reset_index(drop=True)
    print (len(raw_data.Targetted_sp_generic_name.value_counts()))
    if len(raw_data.Targetted_sp_generic_name.value_counts()) == 0:
        print ("Dataframe has no targetted viruses or viroids")
        csv_file1 = open(sample + "_" + read_size + "_all_targets_with_scores.txt", "w")
        csv_file1.write("sacc\tnaccs\tlength\tslen\tcov\tav-pident\tstitle\tqseqids\tRNA_type\targetted_sp_generic_name\tnaccs_score\tlength_score\tavpid_score\tcov_score\tgenome_score\tcompleteness_score\ttotal_score")
        csv_file1.close()
        csv_file2 = open(sample + "_" + read_size + "_top_scoring_targets.txt", "w")
        csv_file2.write("sacc\tnaccs\tlength\tslen\tcov\tav-pident\tstitle\tqseqids\tTargetted_sp_generic_name\tRNA_type\tTargetted_sp_generic_name\tnaccs_score\tlength_score\tavpid_score\tcov_score\tgenome_score\tcompleteness_score\ttotal_score")       
        csv_file2.close()
        csv_file3 = open(sample + "_" + read_size + "_top_scoring_targets_with_cov_stats.txt", "w")
        csv_file3.write("Sample\tsacc\tnaccs\tlength\tslen\tcov\tav-pident\tstitle\tqseqids\tTargetted_sp_generic_name\tRNA_type\tTargetted_sp_generic_name\tnaccs_score\tlength_score\tavpid_score\tcov_score\tgenome_score\tcompleteness_score\ttotal_score\tMean coverage\tRead count\tRead count norm\tRead count norm\tPCT_1X\tPCT_10X\tPCT_20X")
        csv_file3.close()
        exit ()

    print("Applying scoring to blast results to select best hit")
    raw_data["naccs"] = raw_data["naccs"].astype(int)
    raw_data["naccs_score"] = raw_data.groupby("Targetted_sp_generic_name_updated").apply(max_naccs)

    raw_data["length"] = raw_data["length"].astype(int)
    raw_data["length_score"] = raw_data.groupby("Targetted_sp_generic_name_updated").apply(max_length)

    raw_data["av-pident"] = raw_data["av-pident"].astype(float)
    raw_data["avpid_score"] = raw_data.groupby("Targetted_sp_generic_name_updated").apply(max_avpid)
    
    raw_data["cov"] = raw_data["cov"].astype(float)
    raw_data["cov_score"] = raw_data.groupby("Targetted_sp_generic_name_updated").apply(max_cov)

    raw_data["genome_score"] = raw_data["stitle"].apply(genome_score)
    raw_data["completeness_score"] = raw_data["stitle"].apply(completeness_score)
    
    raw_data["total_score"] = raw_data["length_score"] + raw_data["naccs_score"] + raw_data["avpid_score"] + raw_data["cov_score"] + raw_data["genome_score"] + raw_data["completeness_score"].astype(int)
    
    print("Output all hits that match species of interest")
    raw_data.to_csv(sample + "_" + read_size + "_all_targets_with_scores.txt", index=None, sep="\t" )

    print("Remove seconday hits based on contig name")
    unique_contigs = list(set([i.strip() for i in ",".join(raw_data["qseqids"]).split(",")]))

    filtered_data = pd.DataFrame()
    for contig in unique_contigs:
        selected = pd.DataFrame()
        selected = raw_data[raw_data["qseqids"].str.contains(contig)]
        
        if len(selected) == 1:
            filtered_data = filtered_data.append(selected)
        #If contigs hit to multiple viruses and viroids, choose best hit
        elif len(selected)>1:
            # Extract list of spp for a given contig
            Targetted_sp_generic_name_updated_list = selected["Targetted_sp_generic_name_updated"].tolist()
            #This should accomodate several RNAs per virus spp.
            if len(Targetted_sp_generic_name_updated_list) == 1:
                filtered_data = filtered_data.append(selected)
            # If there are several contigs, retain the top hit, remove 2ary hits
            elif len(Targetted_sp_generic_name_updated_list) > 1:
                topmatch = selected["naccs"].max()
                selected = selected[selected["naccs"] == topmatch]
                # Check if there is a tie when selecting by max naccs:
                Targetted_sp_generic_name_updated_list = selected["Targetted_sp_generic_name_updated"].tolist()
                if len(Targetted_sp_generic_name_updated_list) == 1:
                    filtered_data = filtered_data.append(selected)
                # If there is a tie, select next based on av-pidentity
                else:
                    topmatch = selected["av-pident"].max()
                    selected = selected[selected["av-pident"] == topmatch]
                    filtered_data = filtered_data.append(selected)
            
    filtered_data = filtered_data.drop_duplicates()

    print("Only retain the top hits")
    idx = filtered_data.groupby(["Targetted_sp_generic_name_updated"])["total_score"].transform(max) == filtered_data["total_score"]
    filtered_data = filtered_data[idx]
    print(filtered_data.dtypes)

    #select one random hit if tie for top hits:
    print("If there is a tie, select a random sequence out of the top scoring hit")
    final_data = filtered_data.drop_duplicates(subset="Targetted_sp_generic_name_updated", keep="first")
   
    #By setting keep on False, all duplicates are True
    #If there are duplicates in species name (ie RNA types present), then it will drop NaN
    final_data = final_data[~((final_data["Targetted_sp_generic_name"].duplicated(keep=False))&(final_data["RNA_type"].str.contains("NaN")))]
    final_data = final_data.drop(["Targetted_sp_generic_name"], axis=1)
    final_data = final_data.rename(columns={"Targetted_sp_generic_name_updated": "Targetted_sp_generic_name"})
    final_data.to_csv(sample + "_" + read_size + "_top_scoring_targets.txt", index=None, sep="\t")

    target_dict = {}
    target_dict = pd.Series(final_data.Targetted_sp_generic_name.values,index=final_data.sacc).to_dict()
    print (target_dict)

    print("Align reads and derive coverage and depth for best hit")
    if coverage_cal:
        rawfastq_read_counts = (len(open(rawfastq).readlines(  ))/4)
        cov_dict = {}
        PCT_1X_dict = {}
        PCT_10X_dict = {}
        PCT_20X_dict = {}
        read_counts_dict = {}
        read_counts_normalised_dict = {}
        #selected_read_counts_normalised_dict = {}
        rpkm_dict = {}
        for refid, refspname in target_dict.items():
            print (refid)
            print (refspname)
            combinedid = str(refid + " " + refspname).replace(" ","_")

            print("Extract sequence from blast database")
            fastafile = (sample + "_" + read_size + "_" + combinedid + ".fa").replace(" ","_")
            single_fasta_entry = open(fastafile, "w")
            command_line = ["blastdbcmd","-db", blastdbpath, "-entry", refid, \
                         "-outfmt","'%f'"]
            subprocess.call(command_line, stdout=single_fasta_entry)
            single_fasta_entry.close()

            print("Building a bowtie index")
            index=(sample + "_" + read_size + "_" + combinedid).replace(" ","_")
            buildindex = ["bowtie-build","-f", fastafile, index]
            subprocess.call(buildindex)

            print("Aligning original reads")
            samoutput = str(index + ".sam")
            bowtie_output = str(index + "_bowtie_log.txt")
            aligning = ["bowtie", "-q", "-v", "2", "-k", "1", "-p", "4", "-x", index, fastqfiltbysize, "-S", samoutput]
            subprocess.call(aligning, stderr=open(bowtie_output,"w"))

            print("Derive a bam file")
            bamoutput = str(index + ".bam")
            derivebam = ["samtools", "view", "-@", "4", "-bS", samoutput]
            subprocess.call(derivebam, stdout=open(bamoutput,"w"))

            print("Sorting bam file")
            sortedbamoutput = str(index + ".sorted.bam")
            sorting = ["samtools", "sort", "-@", "4", bamoutput, "-o", sortedbamoutput]
            subprocess.call(sorting)

            sortedbamoutput = str(index + ".sorted.bam")
            bamindex = str(index + ".sorted.bam.bai")
            print("Indexing bam file")
            indexing = ["samtools", "index", sortedbamoutput]
            subprocess.call(indexing, stdout=open(bamindex,"w"))
            
            pileup = str(index + ".pileup")
            derivepileup= ["samtools", "mpileup", "-uf", fastafile, sortedbamoutput, "-o", pileup]
            subprocess.call(derivepileup)

            #variant calling
            vcfout = str(index + ".vcf.gz")
            vcfcall = ["bcftools", "call", "-c", pileup, "-Oz", "-o", vcfout]
            subprocess.call(vcfcall)
            
            vcfindex = ["bcftools", "index", vcfout]
            subprocess.call(vcfindex)

            # Normalise indels:
            bcfnormout = str(index + "_norm.bcf")
            bcfnorm = ["bcftools", "norm", "-f", fastafile, vcfout, "-Ob", "-o", bcfnormout]
            subprocess.call(bcfnorm)
            bcfnormoutindex = ["bcftools", "index", bcfnormout]
            subprocess.call(bcfnormoutindex)

            # Filter adjacent indels within 5bp
            bcfnormoutfiltout = str(index + "_norm_flt_indels.bcf")
            bcfnormoutfilt = ["bcftools", "filter", "--IndelGap", "5", bcfnormout, "-Ob", "-o", bcfnormoutfiltout]
            subprocess.call(bcfnormoutfilt)
            bcfnormoutfiltindex = ["bcftools", "index", bcfnormoutfiltout]
            subprocess.call(bcfnormoutfiltindex)

            # Convert bcf to vcf
            vcfnormoutfiltout = str(index + "_sequence_variants.vcf.gz")
            vcfnormoutfilt = ["bcftools", "view", "-Oz", "-o", vcfnormoutfiltout, bcfnormoutfiltout]
            subprocess.call(vcfnormoutfilt)
            vcfnormoutfiltindex = ["bcftools", "index", vcfnormoutfiltout]
            subprocess.call(vcfnormoutfiltindex)

            # Get consensus fasta file
            genomecovbed = str(index + "_genome_cov.bed")
            gencovcall = ["bedtools", "genomecov", "-ibam", sortedbamoutput, "-bga"]
            subprocess.call(gencovcall, stdout=open(genomecovbed,"w"))

            # Assign N to nucleotide positions that have zero coverage
            zerocovbed = str(index + "_zero_cov.bed")
            zerocovcall = ["awk", "$4==0 {print}", genomecovbed]
            subprocess.call(zerocovcall, stdout=open(zerocovbed,"w"))

            maskedfasta = (sample + "_" + read_size + "_" + combinedid + "_masked.fa").replace(" ","_")
            maskedfastaproc = ["bedtools", "maskfasta", "-fi",  fastafile, "-bed", zerocovbed, "-fo", maskedfasta]
            subprocess.call(maskedfastaproc)

            # Derive a consensus fasta file
            consensus = str(index + ".consensus.fasta")
            consensuscall = ["bcftools", "consensus", "-f",  maskedfasta, vcfout, "-o", consensus]
            subprocess.call(consensuscall)

            # Derive Picard statistics 
            print("Running picard")
            picard_output = (index + "_picard_metrics.txt")
            picard = ["picard", "CollectWgsMetrics", "-I", str(sortedbamoutput), "-O", str(picard_output), "-R", str(fastafile), "-READ_LENGTH","22", "-COUNT_UNPAIRED", "true"]
            subprocess.call(picard)

            subprocess.call(["rm","-r", samoutput])
            subprocess.call(["rm","-r", bamoutput])
            for fl in glob.glob(index + "*ebwt"):
                os.remove(fl)

            reflen = ()
            cov = ()
            PCT_1X = ()
            PCT_10X = ()
            PCT_20X = ()
            with open(picard_output) as f:
                a = " "
                while(a):
                    a = f.readline()
                    l = a.find("MEAN_COVERAGE") #Gives a non-negative value when there is a match
                    if ( l >= 0 ):
                        line = f.readline()
                        elements = line.split("\t")
                        reflen, cov, PCT_1X, PCT_10X, PCT_20X = elements[0], elements[1], elements[13],elements[15],elements[17]
            f.close()
            cov_dict[refspname] = cov
            PCT_1X_dict[refspname]  = PCT_1X
            PCT_10X_dict[refspname]  = PCT_10X
            PCT_20X_dict[refspname]  = PCT_20X

            read_counts = ()
            read_counts_normalised = ()
            #selected_read_counts_normalised = ()
            rpkm = ()
            with open(bowtie_output) as bo:
                a = " "
                while(a):
                    a = bo.readline()
                    l = a.find("# reads with at least one alignment:") #Gives a non-negative value when there is a match
                    if ( l >= 0 ):
                        print(a)
                        read_counts = a.split(" ")[7]
                        print(read_counts)
                        rpkm = round(int(read_counts)/(int(reflen)/1000*int(rawfastq_read_counts)/1000000))
                        read_counts_normalised = round(int(read_counts)*1000000/int(rawfastq_read_counts))
                        print(read_counts_normalised)
            
            read_counts_dict[refspname] = read_counts
            read_counts_normalised_dict[refspname] = read_counts_normalised
            rpkm_dict[refspname] = rpkm

        cov_df = pd.DataFrame(cov_dict.items(),columns=["Targetted_sp_generic_name", "Mean coverage"])
        read_counts_df = pd.DataFrame(read_counts_dict.items(),columns=["Targetted_sp_generic_name", "Read count"])
        read_counts_norm_df = pd.DataFrame(read_counts_normalised_dict.items(),columns=["Targetted_sp_generic_name", "Read count norm"])
        #selected_read_counts_norm_df = pd.DataFrame(selected_read_counts_normalised_dict.items(),columns=["Targetted_sp_generic_name", "Selected read count norm"])
        rpkm_df = pd.DataFrame(rpkm_dict.items(),columns=["Targetted_sp_generic_name", "RPKM"])
        
        PCT_1X_df = pd.DataFrame(PCT_1X_dict.items(),columns=["Targetted_sp_generic_name", "PCT_1X"])
        PCT_10X_df = pd.DataFrame(PCT_10X_dict.items(),columns=["Targetted_sp_generic_name", "PCT_10X"])
        PCT_20X_df = pd.DataFrame(PCT_20X_dict.items(),columns=["Targetted_sp_generic_name", "PCT_20X"])

        dfs = [final_data, cov_df, read_counts_df, read_counts_norm_df, rpkm_df, PCT_1X_df, PCT_10X_df, PCT_20X_df]
        full_table = reduce(lambda left,right: pd.merge(left,right,on="Targetted_sp_generic_name"), dfs)
        full_table["Mean coverage"] = full_table["Mean coverage"].astype(float)
        full_table["PCT_1X"] = full_table["PCT_1X"].astype(float)
        full_table["PCT_10X"] = full_table["PCT_10X"].astype(float)
        full_table["PCT_20X"] = full_table["PCT_20X"].astype(float)
        
        full_table.insert(0, "Sample", sample)
        print(full_table)
        full_table.to_csv(sample + "_" + read_size + "_top_scoring_targets_with_cov_stats.txt", index=None, sep="\t",float_format="%.2f")

def max_avpid(df):
    max_row = df["av-pident"].max()
    labels = np.where((df["av-pident"] == max_row),
                    "1",
                    "0")
    return pd.DataFrame(labels, index=df.index).astype(int)

def max_length(df):
    max_row = df["length"].max()
    labels = np.where((df["length"] == max_row),
                        "2",
                        "0")
    return pd.DataFrame(labels, index=df.index).astype(int)

def max_naccs(df):
    max_row = df["naccs"].max()
    labels = np.where((df["naccs"] == max_row),
                        "1",
                        "0")
    return pd.DataFrame(labels, index=df.index).astype(int)

def max_cov(df):
    max_row = df["cov"].max()
    labels = np.where((df["cov"] == max_row),
                        "1",
                        "0")
    return pd.DataFrame(labels, index=df.index).astype(int)

def genome_score(x):
    if "nearly complete sequence" in str(x):
        return -3
    elif "complete sequence" in str(x):
        return 3
    elif "complete genome" in str(x):
        return 3
    elif "polyprotein gene complete cds" in str(x):
        return 3
    else:   
        return 0    

def completeness_score(x):
    if "partial"in str(x):
        return -2
    elif "polymerase protein" in str(x):
        return -2
    elif "RNA-dependent RNA polymerase" in str(x):
        return -2
    else:
        return 0

if __name__ == "__main__":
    main()

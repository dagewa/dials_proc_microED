#!/bin/bash
set -e

# Check dependencies
DIALS_VERSION=$(dials.version | cat | head -1 | awk '{print $NF}')
echo "DIALS version: $DIALS_VERSION"
IFS=. read major minor patch <<< "$DIALS_VERSION"
if [[ "$minor" == "dev" ]]; then
    echo "Development version of DIALS - no version check done"
elif [[ "$major" != "3" || "$minor" -lt "5" ]]; then
    echo "Need DIALS 3.6 or higher"  >&2
    exit 1
fi

# Check script input
if [ "$#" -ne 1 ]; then
    echo "You must supply the location of the data parent directory only"
    exit 1
fi

# Set up directories
PROCDIR=$(pwd)
DATADIR=$(realpath "$1")
if [ ! -d "$DATADIR" ]; then
    echo "$DATADIR is not found"
    exit 1
fi
if [[ "$PROCDIR" -ef "$DATADIR" ]]; then
    echo "Please process in a new location, not the data directory"
    exit
fi

# Install/update FormatSMVCetaD_TUI.py
dxtbx.install_format -u\
    https://raw.githubusercontent.com/dials/dxtbx_ED_formats/master/FormatSMVCetaD_TUI.py

# Set an environment variable to ensure this format class is used to
# read the images, even though they have DETECTOR_SN=unknown and
# BEAMLINE is not set.
export FORCE_SMV_AS_CETAD=1

cd "$PROCDIR"

# Define a set of backstop masks
cat > mask_120.phil <<+
untrusted {
  panel = 0
  polygon = 2046 976 1113 965 1096 968 1070 951 1035 944 994 951 965 977 954 \
            1000 957 1041 974 1071 1000 1091 1033 1099 1070 1093 1098 1076 \
            1118 1046 1138 1044 1146 1039 2046 1044 2046 976
}
+

cat > mask_200.phil <<+
untrusted {
  panel = 0
  polygon = 3 977 978 996 999 973 1020 964 1047 965 1072 985 1080 1011 1075 \
            1038 1056 1056 1018 1061 995 1049 972 1042 4 1027 3 977
}
+

cat > mask_200-6.phil <<+
untrusted {
  panel = 0
  polygon = 1 978 981 997 1004 973 1024 964 1051 964 1067 973 1077 987 1083 \
            1005 1082 1027 1070 1044 1055 1053 1024 1055 1008 1049 986 1041 \
            976 1038 2 1023 1 978
}
+

cat > mask_300.phil <<+
untrusted {
  panel = 0
  polygon = 2045 970 1116 960 1102 962 1072 945 1047 939 1011 942 982 958 965 \
            982 961 1011 967 1038 984 1063 1004 1079 1028 1088 1055 1089 1087 \
            1078 1099 1070 1125 1038 1136 1037 1156 1030 2046 1037 2045 970
}
+

cat > mask_300-3.phil <<+
untrusted {
  panel = 0
  polygon = 2045 972 1071 963 1058 965 1027 946 969 943 946 954 919 991 916 \
            1004 921 1038 938 1067 966 1086 992 1092 1016 1091 1054 1073 1079 \
            1042 1097 1039 1105 1034 1170 1034 2045 1043 2045 972
}
+


# Processing function for one dataset
process_one () {

    DIR=$1
    BEAM_CENTRE=$2
    DISTANCE=$3
    FIND_SPOTS_D_MIN=$4
    MASK=$5

    DATASET="$DIR"/*.img
    N_IMAGES=$(echo $DATASET | wc -w)

    echo "#### PROCESSING $DATASET"
    dials.import "$DATASET"\
        slow_fast_beam_centre="$BEAM_CENTRE"\
        distance="$DISTANCE"
    dials.generate_mask imported.expt "$PROCDIR"/"$MASK"
    dials.apply_mask imported.expt input.mask=pixels.mask
    dials.background masked.expt output.plot=background.png\
        image=1,"$N_IMAGES" d_max=20 d_min=2
    dials.find_spots masked.expt d_max=25\
        d_min="$FIND_SPOTS_D_MIN"
    dials.index strong.refl masked.expt\
        index_assignment.method=local\
        detector.fix=distance space_group=P43212
    dials.refine indexed.{expt,refl} detector.fix=distance
    dials.plot_scan_varying_model refined.expt
    dials.integrate refined.{expt,refl} prediction.d_min=2.2
    dials.scale integrated.{expt,refl}\
        min_Ih=10\
        unmerged_mtz=scaled.mtz merged_mtz=merged.mtz

    # Calculate R_{Friedel} (optional, because dev.dials.r_friedel is
    # not in the path for DIALS release bundles)
    if command -v dev.dials.r_friedel &> /dev/null
    then
        dev.dials.r_friedel hklin=scaled.mtz
    fi
}

process () {

    cd "$PROCDIR"

    # 120-1
    NAME=120-1
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1025,1037 1427 2.4 mask_120.phil
    cd "$PROCDIR"

    # 120-2
    NAME=120-2
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1026,1038 1427 2.4 mask_120.phil
    cd "$PROCDIR"

    # 120-3
    NAME=120-3
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1024,1039 1427 2.4 mask_120.phil
    cd "$PROCDIR"

    # 200-1
    NAME=200-1
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1023,1023 1863 2.4 mask_200.phil
    cd "$PROCDIR"

    # 200-2
    NAME=200-2
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1023,1011 1863 2.4 mask_200.phil
    cd "$PROCDIR"

    # 200-3
    # This one has a high RMSD_Z and could possibly do with a more
    # sophisticated model, perhaps allowing beam drift
    NAME=200-3
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1022,1047 1863 2.4 mask_200.phil
    cd "$PROCDIR"

    # 200-4
    NAME=200-4
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1019,1026 1863 2.4 mask_200.phil
    cd "$PROCDIR"

    # 200-5
    NAME=200-5
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1012,1029 1863 2.4 mask_200.phil
    cd "$PROCDIR"

    # 200-6
    NAME=200-6
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1025,1025 1863 2.4 mask_200-6.phil
    cd "$PROCDIR"

    # 200-7
    NAME=200-7
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1007,1026 1863 2.4 mask_200.phil
    cd "$PROCDIR"

    # 300-1
    NAME=300-1
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1037,1008 2460 2.4 mask_300.phil
    cd "$PROCDIR"

    # 300-2
    NAME=300-2
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1018,1052 2460 2.4 mask_300.phil
    cd "$PROCDIR"

    # 300-3
    NAME=300-3
    mkdir -p "$NAME"
    cd "$NAME"
    process_one "$DATADIR"/"$NAME" 1030,1011 2460 2.4 mask_300-3.phil
    cd "$PROCDIR"

}

compare_merging_stats () {

    cd "$PROCDIR"

    # Use xia2.compare_merging_stats to compare data quality
    mkdir -p compare_merging_stats
    cd compare_merging_stats
    xia2.compare_merging_stats\
        "$PROCDIR"/120-1/scaled.mtz\
        "$PROCDIR"/120-2/scaled.mtz\
        "$PROCDIR"/120-3/scaled.mtz\
        "$PROCDIR"/200-1/scaled.mtz\
        "$PROCDIR"/200-2/scaled.mtz\
        "$PROCDIR"/200-3/scaled.mtz\
        "$PROCDIR"/200-4/scaled.mtz\
        "$PROCDIR"/200-5/scaled.mtz\
        "$PROCDIR"/200-6/scaled.mtz\
        "$PROCDIR"/200-7/scaled.mtz\
        "$PROCDIR"/300-1/scaled.mtz\
        "$PROCDIR"/300-2/scaled.mtz\
        "$PROCDIR"/300-3/scaled.mtz\
        plot_labels="120-1 120-2 120-3 200-1 200-2 200-3 200-4 200-5 200-6 200-7 300-1 300-2 300-3"\
        small_multiples=True\
        size_inches=12,8

    # Use xia2.delta_cchalf to pick out the datasets that agree least
    # well with the others
    xia2.delta_cc_half\
        "$PROCDIR"/120-1/scaled.{expt,refl}\
        "$PROCDIR"/120-2/scaled.{expt,refl}\
        "$PROCDIR"/120-3/scaled.{expt,refl}\
        "$PROCDIR"/200-1/scaled.{expt,refl}\
        "$PROCDIR"/200-2/scaled.{expt,refl}\
        "$PROCDIR"/200-3/scaled.{expt,refl}\
        "$PROCDIR"/200-4/scaled.{expt,refl}\
        "$PROCDIR"/200-5/scaled.{expt,refl}\
        "$PROCDIR"/200-6/scaled.{expt,refl}\
        "$PROCDIR"/200-7/scaled.{expt,refl}\
        "$PROCDIR"/300-1/scaled.{expt,refl}\
        "$PROCDIR"/300-2/scaled.{expt,refl}\
        "$PROCDIR"/300-3/scaled.{expt,refl}

    # The most different seem to be 300-3, 200-1, 120-3, then 300-2

    cd "$PROCDIR"
}

process
compare_merging_stats


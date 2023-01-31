#!/bin/bash
set -e

# Check dependencies
DIALS_VERSION=$(dials.version | cat | head -1 | awk '{print $NF}')
echo "DIALS version: $DIALS_VERSION"
IFS=. read major minor patch <<< "$DIALS_VERSION"
if [[ "$minor" == "dev" ]]; then
    echo "Development version of DIALS - no version check done"
elif [[ "$major" != "3" || "$minor" -lt "7" ]]; then
    echo "Need DIALS 3.7 or higher"  >&2
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

cat > mask_014.phil <<+
untrusted {
  panel = 0
  polygon = 3 1043 705 1016 942 1007 970 998 994 984 1042 986 1069 1000 1082 \
            1021 1086 1050 1079 1076 1060 1100 1032 1113 996 1108 971 1094 \
            949 1068 938 1064 200 1094 6 1102 3 1043
}
+

cat > mask_0.phil <<+
untrusted {
  panel = 0
  circle = 1035 1011 46
}
untrusted {
  panel = 0
  polygon = 2 979 978 998 992 989 1010 1015 1002 1045 979 1037 2 1021 2 979
}
+

# Processing function for one dataset
process_one () {

    DIR=$1
    BEAM_CENTRE=$2
    PEDESTAL=$3
    D_MIN=$4
    D_MAX=$5
    GAIN=$6
    MASK=$7

    DATASET="$DIR"/*.img
    N_IMAGES=$(echo $DATASET | wc -w)
    MID_IMAGE=$(echo "$N_IMAGES"/2 | bc)

    echo "#### PROCESSING $DATASET"
    dials.import "$DATASET"\
        fast_slow_beam_centre="$BEAM_CENTRE"\
        panel.pedestal="$PEDESTAL"
    dials.generate_mask imported.expt "$PROCDIR"/"$MASK"
    dials.apply_mask imported.expt input.mask=pixels.mask
    dials.background masked.expt output.plot=background.png\
        image=1,"$MID_IMAGE","$N_IMAGES" masking.d_max=3 masking.d_min="$D_MIN"
    dials.find_spots masked.expt d_min="$D_MIN" d_max="$D_MAX" kernel_size=5,5 gain="$GAIN"
    dials.index strong.refl masked.expt\
        index_assignment.method=local\
        detector.fix=distance space_group="P21/n"
    dials.refine indexed.{expt,refl} detector.fix=distance
    dials.plot_scan_varying_model refined.expt
    dials.integrate refined.{expt,refl} prediction.d_min="$D_MIN"
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

    # cbz-014
    # Minor rings at 3.64 and 2.24 Å
    # Distortion in the indexed lattice evident looking down b*
    NAME=cbz-014
    mkdir -p "$NAME"
    cd "$NAME"
    #                              BEAM_CENTRE PEDESTAL D_MIN D_MAX GAIN MASK
    process_one "$DATADIR"/"$NAME" 1011,1032   910      0.8   7.0   4    mask_014.phil
    cd "$PROCDIR"

    # cbz-0
    # Multi-lattice: a major lattice and two minor ones, related to the first by
    # rotations of 68° and 142°. Only take the major lattice for processing
    NAME=cbz-0
    mkdir -p "$NAME"
    cd "$NAME"
    #                              BEAM_CENTRE PEDESTAL D_MIN D_MAX GAIN MASK
    process_one "$DATADIR"/"$NAME" 1034,1009   None     0.8   15    2.0  mask_0.phil
    cd "$PROCDIR"

    # cbz-1
    NAME=cbz-1
    mkdir -p "$NAME"
    cd "$NAME"
    #                              BEAM_CENTRE PEDESTAL D_MIN D_MAX GAIN MASK
    process_one "$DATADIR"/"$NAME" 1021,1017   None     0.8   15    2.0  mask_0.phil
    cd "$PROCDIR"

    # cbz-2
    NAME=cbz-2
    mkdir -p "$NAME"
    cd "$NAME"
    #                              BEAM_CENTRE PEDESTAL D_MIN D_MAX GAIN MASK
    process_one "$DATADIR"/"$NAME" 1018,1017   None     0.8   15    2.0  mask_0.phil
    cd "$PROCDIR"

    # cbz-3
    NAME=cbz-3
    mkdir -p "$NAME"
    cd "$NAME"
    #                              BEAM_CENTRE PEDESTAL D_MIN D_MAX GAIN MASK
    process_one "$DATADIR"/"$NAME" 1034,1017   None     0.8   15    2.0  mask_0.phil
    cd "$PROCDIR"

    # cbz-4
    # Poor RMSDs. Split crystal
    NAME=cbz-4
    mkdir -p "$NAME"
    cd "$NAME"
    #                              BEAM_CENTRE PEDESTAL D_MIN D_MAX GAIN MASK
    process_one "$DATADIR"/"$NAME" 1017,991   None     0.85   15    2.0  mask_0.phil
    cd "$PROCDIR"

}

compare_merging_stats () {

    cd "$PROCDIR"

    # Use xia2.compare_merging_stats to compare data quality
    mkdir -p compare_merging_stats
    cd compare_merging_stats
    xia2.compare_merging_stats\
        "$PROCDIR"/cbz-014/scaled.mtz\
        "$PROCDIR"/cbz-0/scaled.mtz\
        "$PROCDIR"/cbz-1/scaled.mtz\
        "$PROCDIR"/cbz-2/scaled.mtz\
        "$PROCDIR"/cbz-3/scaled.mtz\
        "$PROCDIR"/cbz-4/scaled.mtz\
        plot_labels="cbz-014 cbz-0 cbz-1 cbz-2 cbz-3 cbz-4"\
        small_multiples=True\
        size_inches=12,8

    # Use xia2.delta_cchalf to pick out the datasets that agree least
    # well with the others
    xia2.delta_cc_half\
        "$PROCDIR"/cbz-014/scaled.{expt,refl}\
        "$PROCDIR"/cbz-0/scaled.{expt,refl}\
        "$PROCDIR"/cbz-1/scaled.{expt,refl}\
        "$PROCDIR"/cbz-2/scaled.{expt,refl}\
        "$PROCDIR"/cbz-3/scaled.{expt,refl}\
        "$PROCDIR"/cbz-4/scaled.{expt,refl}

    # Best dataset is cbz-014, then cbz-2. Worst is cbz-3?

    cd "$PROCDIR"
}

joint_scale () {

    cd "$PROCDIR"

    mkdir -p joint_scale
    cd joint_scale

    dials.cosym "$PROCDIR"/cbz-014/integrated.{expt,refl}\
                "$PROCDIR"/cbz-0/integrated.{expt,refl}\
                "$PROCDIR"/cbz-1/integrated.{expt,refl}\
                "$PROCDIR"/cbz-2/integrated.{expt,refl}\
                "$PROCDIR"/cbz-3/integrated.{expt,refl}\
                "$PROCDIR"/cbz-4/integrated.{expt,refl}\
                space_group="P21/n"

    # Scale with automated image exclusions, absorption forced off
    dials.scale symmetrized.expt symmetrized.refl d_min=0.8\
        filtering.method=deltacchalf\
        deltacchalf.mode=image_group\
        physical.absorption_correction=False\
        min_Ih=10\
        output.experiments=scaled.expt output.reflections=scaled.refl\
        unmerged_mtz=joint_scaled.mtz merged_mtz=joint_merged.mtz

    # ΔCC½ analysis removes no image ranges here

    cd "$PROCDIR"
}

solve () {
    cd "$PROCDIR"

    mkdir -p shelx
    cd shelx

    mtz2hkl -f -o cbz.hkl $PROCDIR/joint_scale/joint_scaled.mtz
    #xia2.to_shelx $PROCDIR/joint_scale/joint_scaled.mtz cbz
    CELL=$(gemmi mtz -d $PROCDIR/joint_scale/joint_scaled.mtz | grep -m 1 cell | cut -c13-)
    WAVELENGTH=$(gemmi mtz -d $PROCDIR/joint_scale/joint_scaled.mtz | tac | grep -m 1 wavelength | cut -c13-)
    edtools.make_shelx -c $CELL -w $WAVELENGTH -s "P 21/n" -m "C15 H12 N2 O"
    mv shelx.ins cbz.ins
    shelxt cbz | tee shelxt.log

    cd "$PROCDIR"
}

#process
#compare_merging_stats
#joint_scale
solve

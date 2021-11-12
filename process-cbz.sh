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

cat > mask.phil <<+
untrusted {
  panel = 0
  polygon = 3 1043 705 1016 942 1007 970 998 994 984 1042 986 1069 1000 1082 \
            1021 1086 1050 1079 1076 1060 1100 1032 1113 996 1108 971 1094 \
            949 1068 938 1064 200 1094 6 1102 3 1043
}
+

dials.import "$DATADIR"/cbz-014/*.img\
        slow_fast_beam_centre=1032,1011\
        panel.pedestal=910
dials.generate_mask imported.expt mask.phil
dials.apply_mask imported.expt input.mask=pixels.mask
# First image has high background values. This drops during the data
# collection, rapidly at first and then more slowly
dials.background masked.expt output.plot=background.png\
    image=1,48,96 d_max=3
dials.find_spots masked.expt d_min=0.7 d_max=7 kernel_size=5,5 gain=4
dials.find_rotation_axis masked.expt strong.refl
dials.index strong.refl optimised.expt\
    index_assignment.method=local\
    detector.fix=distance space_group="P21/n"
dials.refine indexed.{expt,refl} detector.fix=distance
dials.plot_scan_varying_model refined.expt
dials.integrate refined.{expt,refl} prediction.d_min=0.7
dials.scale integrated.{expt,refl}\
    min_Ih=10\
    unmerged_mtz=scaled.mtz merged_mtz=merged.mtz


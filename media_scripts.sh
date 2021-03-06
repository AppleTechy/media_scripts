#!/bin/bash

## ffmpeg batch script
## processes all files in a directory recursively

#IFS=$'\n'
shopt -s nullglob # prevent null files
shopt -s globstar # for recursive for loops


# start with map for video, add to it later
using_libx264=false;
using_libx265=false;
autosubs=false;
map_all_eng=false;
audio_metadata=""
indir=false
outdir=false
preview=false
onefile=false
twopass=false
profile=""
mode=""
sub_metadata="-metadata:s:s:0 Title=\"English\" -metadata:s:s:0 language=eng"

# other general options
# -n tells ffmpeg to skip files if completed, not necessary anymore since we 
# check in the script before executing, but doesn't hurt to keep
# also silence the initial ffmpeg prints and turn stats back on
verbosity="-hide_banner -v fatal -stats"


#print helpful usage to screen
usage() { echo "Usage: ffmpeg_helper <in_dir> <out_dir>" 1>&2; exit 1; }

# grab input and output directories
indir=$1
outdir=$2

# check arguments were given
if [ $indir == false ]; then
	echo "missing input directory"
	usage
fi
if [ $outdir == false ]; then
	echo "missing output directory"
	usage
fi

echo "input directory:"
echo $indir
echo "output directory:"
echo $outdir

# ask container options
echo " "
echo "what do you want to make?"
echo "mkv, mp4, and srt options make one output with ffmpeg"
echo "all_subs will use mkvmerge to extract all subtitles in any format"
select opt in "mkv" "mp4" "srt" "all_subs"; do
	case $opt in
	mkv ) 
		container="mkv"
		format="matroska"
		sopts="-c:s copy"
		vmaps="-map 0:v:0"
		video_metadata="-metadata:s:v:0 Title=\"Track 1\" -metadata:s:v:0 language=eng"
		audio_metadata="-metadata:s:a:0 Title=\"Track 1\" -metadata:s:a:0 language=eng"
		mode="video"
		break;;
	mp4 )
		container="mp4"
		format="mp4"
		sopts="-c:s mov_text"
		vmaps="-map 0:v:0"
		video_metadata="-metadata:s:v:0 Title=\"Track 1\" -metadata:s:v:0 language=eng"
		audio_metadata="-metadata:s:a:0 Title=\"Track 1\" -metadata:s:a:0 language=eng"
		mode="video"
		break;;
	srt )
		container="srt"
		sopts="-c:s srt"
		smaps="-map 0:s:0"
		force_external_sub=false;
		mode="srt"
		break;;
	all_subs )
		mode="all_subs"
		break;;
	*)
		echo "invalid option"
		esac
done

if [ $mode == "video" ]; then
	# ask video codec question
	echo " "
	echo "Which Video codec to use?"
	select opt in "x264_2pass_10M" "x264_2pass_7M" "x264_2pass_3M" "x264_rf18" "x264_rf20"  "x265_2pass_25M" "x265_rf21" "copy"; do
		case $opt in
		copy )
			vopts="-c:v copy"
			break;;
		x264_2pass_10M )
			vopts="-c:v libx264 -preset slow -b:v 10000k"
			profile="-profile:v high -level 4.1" 
			using_libx264=true;
			twopass="x264";
			break;;
		x264_2pass_7M )
			vopts="-c:v libx264 -preset slow -b:v 7000k"
			profile="-profile:v high -level 4.1" 
			using_libx264=true;
			twopass="x264";
			break;;
		x264_2pass_3M )
			vopts="-c:v libx264 -preset slow -b:v 3000k"
			profile="-profile:v baseline -level 3.1"
			using_libx264=true;
			twopass="x264";
			break;;
		x264_rf18 )
			vopts="-c:v libx264 -preset slow -crf 18"
			profile="-profile:v high -level 4.1" 
			using_libx264=true;
			break;;
		x264_rf20 )
			vopts="-c:v libx264 -preset slow -crf 20"
			profile="-profile:v high -level 4.1" 
			using_libx264=true;
			break;;
		x265_2pass_25M )
			vopts="-c:v libx264 -preset slow -b:v 25000k -x265-params profile=main10:level=5.0"
			twopass="x265";
			break;;
		x265_rf21 )
			vopts="-c:v libx265 -preset slow -x265-params profile=main10:crf=21"
			break;;
		*)
			echo "invalid option"
			esac
	done

	# ask delinterlacing filter question
	echo " "
	echo "use delinterlacing filter?"
	echo "bwdif is a better filter but only works on newer ffmpeg"
	echo "cropping takes off 2 pixels from top and bottom which removes"
	echo "some interlacing artifacts from old dvds"
	select opt in "none" "w3fdif" "w3fdif_crop" "bwdif" "bwdif_crop" "hflip"; do
		case $opt in
		none )
			filters=""
			break;;
		w3fdif )
			filters="-vf \"w3fdif\""
			break;;
		w3fdif_crop )
			filters="-vf \"crop=in_w:in_h-4:0:2, w3fdif\""
			break;;
		bwdif )
			filters="-vf \"bwdif\""
			break;;
		bwdif_crop )
			filters="-vf \"crop=in_w:in_h-4:0:2, bwdif\""
			break;;
		hflip )
			filters="-vf \"hflip\""
			break;;
		*)
			echo "invalid option"
			esac
	done

	# ask audio tracks question
	echo " "
	echo "Which audio tracks to use?"
	#echo "note, mapping all english audio tracks also maps all english subtitles"
	#echo "and subtitle mode is forced to auto"
	select opt in  "first" "second" "all_english" "all" "first+commentary" ; do
		case $opt in
		all_english)
			amaps="-map 0:a:m:language:eng"
			map_all_english=true
			break;;
		first )
			amaps="-map 0:a:0"
			break;;
		second )
			amaps="-map 0:a:1"
			break;;
		all )
			amaps="-map 0:a"
			break;;
		first+commentary )
			amaps="-map 0:a:0 -map 0:a:1"
			audio_metadata="-metadata:s:a:1 Title=\"English\" -metadata:s:a:1 Title=\"Commentary\" -metadata:s:a language=eng"
			break;;
		*)
		echo "invalid option"
		esac
	done

	# ask audio codec question
	echo " "
	echo "Which audio codec to use?"
	select opt in "aac_5.1" "aac_stereo" "aac_stereo_downmix" "copy"; do
		case $opt in
		aac_stereo )
			aopts="-c:a aac -b:a 128k"
			break;;
		aac_stereo_downmix )
			aopts="-c:a aac -b:a 128k"
			aopts="$aopts -af \"pan=stereo|FL < 1.0*FL + 0.707*FC + 0.707*BL|FR < 1.0*FR + 0.707*FC + 0.707*BR\""
			break;;
		aac_5.1 )
			aopts="-c:a aac -b:a 384k"
			break;;
		copy )
			aopts="-c:a copy"
			break;;
		*)
		echo "invalid option"
		esac
	done

	# ask subtitle question
	echo " "
	echo "What to do with subtitles?"
	echo "Auto will select external srt if available"
	echo "otherwise will grab first embedded sub"
	select opt in "auto" "keep_first" "keep_second" "keep_all" "none"; do
		case $opt in
		auto)
			autosubs=true;
			break;;
		keep_all )
			smaps="-map 0:s"
			break;;
		keep_first )
			smaps="-map 0:s:0"
			break;;
		keep_second )
			smaps="-map 0:s:1"
			break;;
		none )
			break;;
		*)
		echo "invalid option"
		esac
	done
fi #end check for non-srt containers

if [ $mode == "video" ]; then
	# ask run options
	echo " "
	echo "preview ffmpeg command, do a 1 minute sample, 60 second sample, or run everything now?"
	select opt in "preview" "run_now" "run_verbose" "sample1" "sample60" "sample60_middle" "run_now_no_chapters"; do
		case $opt in
		preview ) 
			lopts=""
			preview=true
			break;;
		run_now ) 
			lopts=""
			break;;
		run_verbose ) 
			lopts=""
			verbosity="-stats"
			break;;
		sample1 )
			lopts="-t 00:00:01.0"
			break;;
		sample60 )
			lopts="-t 00:01:00.0"
			break;;
		sample60_middle )
			lopts="-ss 00:02:00.0 -t 00:01:00.0"
			break;;
		run_now_no_chapters ) 
			lopts=""
			vmaps="$vmaps -map_chapters -1"
			break;;
		*)
			echo "invalid option"
			esac
	done
else
	# ask run options when extracting just subtitles
	echo " "
	echo "preview command, or run now?"
	select opt in "preview" "run_now"; do
		case $opt in
		preview ) 
			lopts=""
			preview=true
			break;;
		run_now ) 
			lopts=""
			break;;
		*)
			echo "invalid option"
			esac
	done
fi


# see if one file instead of a directory was given
if [[ -f $indir ]]; then
	echo "acting on just one file"
	echo " "
	onefile=true
	FILES=$indir
else
	FILES="$(find "$indir" -type f -iname \*.mkv -o -iname \*.MKV -o -iname \*.mp4 -o -iname \*.MP4 -o -iname \*.AVI -o -iname \*.avi | sort)"
fi

#set IFS to fix spaces in file names
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

################################################################################
# loop through all input files
################################################################################
for ffull in $FILES
do
	if [ $onefile == false ]; then
		# ffull is complete path from root
		# strip extension, still includes subdir!
		fpath="${ffull%.*}" 
		# strip all path to get juts the name
		fname=$(basename "$fpath") 
		# to get subdir, start by stripping the name
		subdir="${fpath%$fname}"
		# then strip indir to get realtive path
		subdir="${subdir#$indir}" 
		# final directory of indir to keep in output
		indirbase=$(basename "$indir") 
		# directory to make later
		outdirfull="$outdir$indirbase/$subdir" 
		# place in outdir with mkv extension
		out_no_ext="$outdirfull$fname"
		outfull="$out_no_ext.$container" 
	else
		# strip extension, still includes subdir
		fpath="${ffull%.*}"
		# strip all path to get juts the name
		fname=$(basename "$fpath") 
		# directory to make later
		outdirfull="$outdir" 
		out_no_ext="$outdir$fname"
		# place in outdir with mkv extension
		outfull="$out_no_ext.$container"
	fi
	
	##debugging stuff
	#echo "paths:"
	#echo "$indir"
	#echo "$outdir"
	#echo "$ffull"
	#echo "$fpath"
	#echo "$fname"
	#echo "$subdir"
	#echo "$indirbase"
	#echo "$outdirfull"
	#echo "$outfull"
	
################################################################################
# mkvextract stuff, ffmpeg stuff below
################################################################################
	if [ $mode == "all_subs" ]; then
	
		command="mkvextract tracks \"$ffull\""

		# count number of each type of sub
		numpgs=0
		numsrt=0
		numother=0
		while read subline
		do
			if [[ $subline == *"SRT"* ]]; then
				numsrt=$((numsrt+1))
			elif  [[ $subline == *"PGS"* ]]; then
				numpgs=$((numpgs+1))
			else
				numother=$((numother+1))
			fi		
		done < <(mkvmerge -i "$ffull" | grep 'subtitles' ) # process substitution

		# Find out which tracks contain the subtitles
		while read subline
		do
			# Grep the number of the subtitle track
			tracknumber=`echo $subline | egrep -o "[0-9]{1,2}" | head -1`
			# add track to the command
			if [[ $subline == *"SRT"* ]]; then
				if [[ $numsrt -lt 2 ]]; then
					command="$command $tracknumber:\"$out_no_ext.srt\""
				else
					command="$command $tracknumber:\"$out_no_ext.$tracknumber.srt\""
				fi
			elif  [[ $subline == *"PGS"* ]]; then
				if [[ $numpgs -lt 2 ]]; then
					command="$command $tracknumber:\"$out_no_ext.pgs\""
				else
					command="$command $tracknumber:\"$out_no_ext.$tracknumber.pgs\""
				fi
			else
				if [[ $numsrt -lt 2 ]]; then
					command="$command $tracknumber:\"$out_no_ext.sub\""
				else
					command="$command $tracknumber:\"$out_no_ext.$tracknumber.sub\""
				fi
			fi
		done < <(mkvmerge -i "$ffull" | grep 'subtitles' ) # process substitution
		
		# finished constructing command by silencing mkvextract
		command="$command > /dev/null 2>&1"
		
		if [ $preview == true ]; then
			echo "available subs for $ffull"
			mkvmerge -i "$ffull" | grep 'subtitles'
			echo "would run:"
			echo "$command"
			echo " "
		else
			echo "starting $ffull"
			mkdir -p "$outdirfull" # make sure output directory exists
			if eval "$command"; then
				echo "success!"
				echo " "
			else
				echo " "
				echo "mkvextract failure"
				echo " "
				exit
			fi
		fi
			

    
################################################################################
# ffmpeg stuff, mkvextract above
################################################################################
	else
		# arguments that must be reset each time since they may change between files
		ins=" -i \"$ffull\""

		# skip if file is already complete
		if [ -f "$outfull" ]; then
			echo "completed: $ffull"
			echo "already exists: $outfull"
			continue
		fi

		# if using autosubs, check if externals exist
		if [ $autosubs == true ]; then
			if [ -f "$fpath.srt" ]; then
				ins="$ins -i \"$fpath.srt\""
				smaps="-map 1:s"
			else
				smaps="-map 0:s:0"
			fi
		fi

		#combine options into ffmpeg string
		maps="$vmaps $amaps $smaps"
		metadata="-metadata title=\"$fname\" $video_metadata $audio_metadata $sub_metadata"
		#metadata="$video_metadata $audio_metadata $sub_metadata"
		if [ $twopass == "x264" ]; then
			command="echo \"pass 1 of 2\" && ffmpeg -y $verbosity $ins $maps $vopts -pass 1 $profile $lopts $filters $aopts $sopts $metadata -f $format /dev/null && echo \"pass 2 of 2\" && ffmpeg -n $verbosity $ins $maps $vopts -pass 2 $profile $lopts $filters $aopts $sopts $metadata \"$outfull\""
		elif [ $twopass == "x265" ]; then
			command="echo \"pass 1 of 2\" && ffmpeg -y $verbosity $ins $maps $vopts:pass=1 $profile $aopts -f $format /dev/null && echo \"pass 2 of 2\" && ffmpeg -n $verbosity $ins $maps $vopts:pass=2 $profile $lopts $filters $aopts $sopts $metadata \"$outfull\""
		else
			command="ffmpeg -n $verbosity $ins $maps $vopts $profile $lopts $filters $aopts $sopts $metadata \"$outfull\""
		fi
	
		# off we go!!
		if $preview ; then
			echo " "
			echo "preview:"
			echo " "
			echo "would make directory:"
			echo "$outdirfull"
			echo "command:"
			echo "$command"
		
		else
			mkdir -p "$outdirfull" # make sure output directory exists
			echo " "
			echo "starting:"
			echo "in:  $ffull"
			echo "out: $outfull"
			echo " "
			if eval "$command"; then
				echo "success!"
				echo " "
			else
				echo " "
				echo "ffmpeg failure: $f"
				echo " "
				exit
			fi
		fi
	fi
done
# restore $IFS
IFS=$SAVEIFS

echo " "
echo "DONE"




#!/bin/bash

script="$(realpath $0)"
scriptDir="$(dirname $script)"
export PATH=$scriptDir:"$scriptDir/scripts":$PATH

set -o errexit
set -o nounset

# Edit these parameters
#refDate="01-JAN-2020.06:00:00"
refDate=`date -Iseconds`
viewTag="riezebosch_dynamic"
vobTag="CodeToCloud"
vobDirs="*"

mvfsKey="HKLM\\SYSTEM\\CurrentControlSet\\services\\Mvfs\\Parameters"
viewDrive="$(reg query $mvfsKey //v drive | perl -ane 'if (/drive/) { print uc pop @F }')"
viewDir="/$viewDrive/$viewTag/$vobTag"
viewDirWin="$viewDrive:\\$viewTag\\$vobTag"

workingDir="$(pwd)"
workingDirWin="$(pwd -W | perl -pe 's/\//\\\\/g')"

cd "$viewDir"
set +o nounset

cd "$workingDir"
if [ ! -d git-import ]; then
    mkdir git-import
fi
cd git-import

rm -rf export
if [ ! -d export ]; then
    mkdir export
fi

echo "$refDate" > import-date.txt
cd "$viewDir"

# one clearexport_ccase for each directory, do that 1) it doesn't crash (out of memory), 2) it is parallelized
# only od folders we can actually see. it's just to optimize
cc_export=0
root=$viewDir
real_root="$(basename "$root")"
if [ ! -f "$workingDir/git-import/export/$real_root.export" ]; then
	echo "Exporting $real_root..."
	clearexport_ccase -r -o "$workingDirWin\\git-import\\export\\$real_root.export" "." > "$workingDir/git-import/export/$real_root.export.log" &
	cc_export=1
	sleep 5 # give it a bit of time to start
fi

cd "$workingDir/git-import/export"
if [ $cc_export -eq 1 ]; then
    working=1
    while [ $working ]; do
        working=
        echo -n "Waiting for"
        for f in *.export; do
            # clearcase export files are empty until everything is finished
            if [ ! -s "$f" ]; then
                echo -n " $f"
                working=1
            fi
        done
        echo "..."
        sleep 15
    done
fi

cd "$viewDir"
if [ ! -f "$workingDir/git-import/export/all_dirs" ]; then
    echo "Finding directories..."
    cleartool find -all -type d -print | sort -r > "$workingDir/git-import/export/all_dirs"
fi

if [ ! -f "$workingDir/git-import/export/all_files" ]; then
    echo "Finding files..."
    cleartool find -all -type f -print | sort -r > "$workingDir/git-import/export/all_files"
fi

cd "$workingDir/git-import/export"

if [ ! -f to_import.dirs ]; then
    perl "$scriptDir/filter.pl" all_dirs > to_import.dirs
fi

if [ ! -f to_import.files ]; then
    perl "$scriptDir/filter.pl" all_files > to_import.files
fi

if [ ! -f fullVobDB.bin ]; then
    GitImporter.exe -S:fullVobDB.bin -E:to_import.files -D:to_import.dirs -C:"$viewDirWin" -O:"$refDate" -G *.export
    mv "$scriptDir/GitImporter.log" build_vobdb.log
fi

cd "$workingDir/git-import"

if [ ! -f export/fullVobDB.bin ]; then
    echo "File fullVobDB.bin not found"
    exit 1
fi

if [ ! -d git-repo ]; then
    mkdir git-repo
fi

if [ -f "$scriptDir/GitImporter.log" ]; then
    rm "$scriptDir/GitImporter.log"
fi

for r in export/*.export; do
    root="$(basename "${r%.export}")"

    # Check if we need to redo.
    if [ -d "git-repo/$root" ]; then
        cd "git-repo/$root"
        if [ -z "$(git branch -a)" ]; then
            cd ../..
            rm -rf "git-repo/$root"
        else
            cd ../..
        fi
    fi

    if [ ! -d "git-repo/$root" ]; then
        echo "Importing $root..."
        if [ -e "history-$root.bin.bak" ]; then
            rm "history-$root.bin.bak"
        fi

        GitImporter.exe -L:export/fullVobDB.bin -I:../gitignore -H:"history-$root.bin" -C:"$viewDirWin" -N -R:"$viewDirWin\\$root" > "to_import_full_$root"
        mv "$scriptDir/GitImporter.log" "create_changesets-$root.log"

        export GIT_DIR="$workingDir/git-import/git-repo/$root"
        git init "$GIT_DIR"
        git config core.ignorecase false

        GitImporter.exe -C:"$viewDirWin" -F:"to_import_full_$root" -R:"$viewDirWin\\$root" | tee /dev/null | git fast-import --export-marks="git-marks-$root.marks"
        mv "$scriptDir/GitImporter.log" "create_repo-$root.log"

        echo "Repacking repo..."
        git repack -a -d -f
    fi
    unset root
done

echo "Done!"

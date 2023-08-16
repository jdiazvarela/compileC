#!/bin/sh


### --- CONFIGS

BIN_SUBFOLDER='bin';
SRC_SUBFOLDER='src';
DLL_SUBFOLDER='dll.d';
MAIN_SRC_FILENAME='main.c';

COMPILER='gcc';
FLAGS='-pass-exit-codes -Wextra -fmax-errors=4';
FLAGS_DEFAULT_MAIN='-l dl';

LOOP_DELAY=2;
FULL_UPDATE_LAPSE=10;


### --- VARS

MAIN_SRC_FILENAME_REGEXP='';
SRC_FOLDER='';
SRC_FOLDER_REGEXP='';
BIN_FOLDER='';
DLL_FOLDER='';
ROOT_FOLDERS_REGEXP='';
MAIN_PID='';


### --- MAIN

mainLoop() {

	checkEnv || return $?;

	_DLLS='';
	findDlls || return $?;
	if [ "${DLLS}" != "${_DLLS}" ] || [ ${curretTimestamp} -gt $(( ${lastFullUpdate} + ${FULL_UPDATE_LAPSE} )) ]; then
		DLLS="${_DLLS}";
		DLLS_regexp="$( text_toRexp "${DLLS}" )";
		# update all targets
		_LAST_MODIFICATION='';
		_DEPENDENCIES='';
		fullInfoUpdate || return $?;
		LAST_MODIFICATION="${_LAST_MODIFICATION}";
		DEPENDENCIES="${_DEPENDENCIES}";
		[ ${curretTimestamp} -gt $(( ${lastFullUpdate} + ${FULL_UPDATE_LAPSE} )) ] && lastFullUpdate="${curretTimestamp}";
	fi;

	TO_COMPILE='';
	getCompileCandidates || return $?;

	# is there something to do?
	if [ -n "${TO_COMPILE}" ]; then

		local i='';
		for i in $( seq "$( text_lineCount "${TO_COMPILE}" )" ); do

			local ifs="${IFS}";
			local target='';
			IFS_toNewLine;
			for target in $( printf '%s\n' "${TO_COMPILE}" ); do
				IFS="${ifs}";

				local regexp="$( text_toRexp "${target}" )";

				# skip targets with not compiled dependencies
				local dependencies="$( printf '%s' "${DEPENDENCIES}" | sed -n 's/^'"${regexp}"';//; t_ok; b; :_ok; s/;/\n/g; p;' )";
				if [ -n "${dependencies}" ]; then
					dependencies="$( printf '%s' "${dependencies}" | sed -n '/^\('"$( text_toRexp "${TO_COMPILE}" )"'\)$/p' )";
					if [ -n "${dependencies}" ]; then
						continue;
					fi;
				fi;

				checkLibsDefined "${target}" || continue;
				if ! compileTarget "${target}"; then
					Error 1 "while compiling '${target}'";
					continue;
				fi;
				updateLastModificationTimestamp "${target}" || return $?;

				TO_COMPILE="$( printf '%s' "${TO_COMPILE}" | sed '/^'"${regexp}"'$/d' )";
			done;
			IFS="${ifs}";

			[ -z "${TO_COMPILE}" ] && break;
		done;

		if [ -n "${TO_COMPILE}" ]; then
			msgCompilationNotFinished;
			return 1;
		else
			msgCompilationFinished;
			return 0;
		fi;
	fi;
};

main() {

	setEnv || return $?;
	checkEnv || return $?;

	local _DLLS='';
	findDlls || return $?;
	local DLLS="${_DLLS}";
	local DLLS_regexp="$( text_toRexp "${DLLS}" )";

	local _LAST_MODIFICATION='';
	local _DEPENDENCIES='';
	fullInfoUpdate || return $?;
	local LAST_MODIFICATION="${_LAST_MODIFICATION}";
	local DEPENDENCIES="${_DEPENDENCIES}";

	local lastFullUpdate="$( date +%s )";
	local curretTimestamp='';
	local firstRun=0;

	local TO_COMPILE='';
	while true; do
		curretTimestamp="$( date +%s )";
		if [ ${firstRun} -eq 0 ]; then
			msgInit;
		fi;
		if mainLoop; then
			if [ ${firstRun} -eq 0 ]; then
				if [ -z "${MAIN_PID}" ]; then
					"${BIN_FOLDER}/$( getCompilationOutputSubPath "${MAIN_SRC_FILE}" )" 1>"${RUN_STDOUT_PATH}" 2>"${RUN_STDERR_PATH}" &
					MAIN_PID=$!;
				fi;
			fi;
		fi;
		firstRun=1;
		sleep "${LOOP_DELAY}";
	done;

	return 0;
};


### --- MESSAGES

msgDate() { :
	date +' %Y-%m-%d %H:%M:%S ';
};

msgInfo() {
	printf '%s' "$( msgDate ):";
};

msgInit() { :
	printf '%s\n' "$( msgInfo ) INIT";
	printf '\n';
};

msgCompilationNotFinished() { :
	printf '%s\n' "$( msgInfo ) UNABLE TO FINISH PROJECT COMPILATION";
	printf '\n';
};

msgCompilationFinished() { :
	printf '%s\n' "$( msgInfo ) PROJECT COMPILED";
	printf '\n';
};

# $*: command
msgCommand() { :
	[ -z "$*" ] && return 0;
	echo "$( msgDate ):> CMD: $*";
};

# $*: path
msgCd() {
	msgCommand "$( \
		printf '%s' "${currentLocation}" \
		| \
		sed '
			/^\('"${ROOT_FOLDERS_REGEXP}"'\)$/d
			s/^\('"${ROOT_FOLDERS_REGEXP}"'\)\//cd '"'"'{{ROOT}}\//;
			t_ok;
			b;
			:_ok;
			s/$/'"'"'/;
		' \
	)";
}

# $*: filepath
msgModificationDetected() { :
	local target="$( printf '%s' "$*" | sed 's/^\('"${ROOT_FOLDERS_REGEXP}"'\)\///;' )";
	echo "$( msgInfo ) file modified since last time '${target}'";
};

# $1: filepath
# $2-*: output path
msgMissingOutput() { :
	local target="$( printf '%s' "$1" | sed 's/^\('"${ROOT_FOLDERS_REGEXP}"'\)\///;' )";
	shift 1;
	local output="$( printf '%s' "$*" | sed 's/^\('"${ROOT_FOLDERS_REGEXP}"'\)\///;' )";
	echo "$( msgInfo ) source code '${target}' with missing binary '${output}'";
};

# $*: filepath
msgUpdateLastModificationTimestamp() { :
	local target="$( printf '%s' "$*" | sed 's/^\('"${ROOT_FOLDERS_REGEXP}"'\)\///;' )";
	#echo "$( msgInfo ) source code '$1' with missing binary '$2'";
};

# $*: filepath
msgLoadedCompilationNotes() { :
	local target="$( printf '%s' "$*" | sed 's/^\('"${ROOT_FOLDERS_REGEXP}"'\)\///;' )";
	echo "$( msgInfo ) compilation notes loaded for '${target}'";
};

# $1: filepath
# $2-*: affected files
msgAffectedByDependencies() { :
	local target="$( printf '%s' "$1" | sed 's/^\('"${ROOT_FOLDERS_REGEXP}"'\)\///;' )";
	shift 1;
	local affected="$( printf '%s' "$*" | sed 's/^\('"${ROOT_FOLDERS_REGEXP}"'\)\///;' | sed ':c;$!{N;bc;};s/\n/'"'"', '"'"'/g;s/^\s*/'"'"'/;s/$/'"'"'/;' )";
	echo "$( msgInfo ) file '${target}' affects ${affected}";
};


### --- STUFF

# $*: filepath
updateLastModificationTimestamp() {

	local temporal='';
	temporal="$( find "$*" -printf '%Ts\n' )";
	Error $? "obtaining last modification date of file '$*'" || return $?;

	local regexp="$( text_toRexp "$*" )";

	temporal='s/^[^;]*;\('"${regexp}"'\)$/'"${temporal}"';\1/';

	LAST_MODIFICATION="$( printf '%s' "${LAST_MODIFICATION}" | sed "${temporal}" )";

	printf '%s' "${LAST_MODIFICATION}" > "${LAST_MODIFICATION_FILE}";
	Error $? "updating last modifications list '${LAST_MODIFICATION_FILE}'" || return $?;

	msgUpdateLastModificationTimestamp "$*";

	return 0;
};

# $*: filepath
isHeader() { printf '%s' "$*" | sed -n '/\.[hH]$/q33'; [ $? -eq 33 ]; };

# $*: filepath
isCNotes() { printf '%s' "$*" | sed -n '/\.[cC][nN][oO][tT][eE][sS]$/q33'; [ $? -eq 33 ]; };

# ENV: DLLS_regexp
# $*: filepath
isDll() { printf '%s' "$*" | sed -n '/^\('"${DLLS_regexp}"'\)$/q33'; [ $? -eq 33 ]; };

# $*: filepath
findMainFilename() {

	local temporal='';
	temporal="$( find -L "$*" -mindepth 1 -maxdepth 1 -type f )";
	Error $? "searching main source file on '$*'" || return $?;

	temporal="$( \
		printf '%s' "${temporal}" \
		| \
		sed -n "${MAIN_SRC_FILENAME_REGEXP}" \
		| \
		sort \
		| \
		sed '/^\s*$/d; q;' \
	)";
	[ -n "${temporal}" ] || return $?;

	printf '%s' "${temporal}";
};

# $*: filepath
getCompilationOutputSubPath() {

	# different place for dlls
	if [ "$*" != "${MAIN_SRC_FILE}" ] && isDll "$*"; then
		printf '%s' "$*" | sed 's/^'"${SRC_FOLDER_REGEXP}"'\///; :_none; t_none; s/\([^/]\+\)\/\([^/]\+\)$/\1.so/; t_end; s/\.[cC]$/.so/; t_end; :_end;';
	else
		printf '%s' "$*" | sed 's/^'"${SRC_FOLDER_REGEXP}"'\///; s/\.[cC]$/.o/;'
	fi;
};

# $*: filepath
getCompilationOutputRelativePath() {
	printf '%s' "$( printf '%s' "$*" | sed 's/^'"${SRC_FOLDER_REGEXP}"'\///; s/[^/]/./g; s/\.\+/../g;' )/${BIN_SUBFOLDER}/$( getCompilationOutputSubPath "$*" )";
};

# $*: filepath
findCompileNotesFile() {

	local temporal='';

	temporal="$( find -L "$( dirname "$*" )" -mindepth 1 -maxdepth 1 -type f )";
	Error $? "searching compiler notes for file '$*'" || return $?;

	printf '%s' "${temporal}" \
	| \
	sed -n '/^\(.*\/\)\?'"$( \
		basename "$*" \
		| \
		sed '
			y/AEIOUÄÁÂÀËÉÊÈÏÍÎÌÖÓÔÒÜÚÛÙBCDFGHJKLMNPQRSTVWXYZÇÑ/aeiouäáâàëéêèïíîìöóôòüúûùbcdfghjklmnpqrstvwxyzçñ/;
			:_none; t_none;
			s/\.c$/\\.cnotes/; t_ok;
			:_ok;
			s/[a]/[aA]/g; s/[à]/[àÀ]/g; s/[â]/[âÂ]/g; s/[á]/[áÁ]/g; s/[ä]/[äÄ]/g;
			s/[b]/[bB]/g; s/[c]/[cC]/g; s/[d]/[dD]/g;
			s/[e]/[eE]/g; s/[è]/[èÈ]/g; s/[ê]/[êÊ]/g; s/[é]/[éÉ]/g; s/[ë]/[ëË]/g;
			s/[f]/[fF]/g; s/[g]/[gG]/g; s/[h]/[hH]/g;
			s/[i]/[iI]/g; s/[ì]/[ìÌ]/g; s/[î]/[îÎ]/g; s/[í]/[íÍ]/g; s/[ï]/[ïÏ]/g;
			s/[j]/[jJ]/g; s/[k]/[kK]/g; s/[l]/[lL]/g; s/[m]/[mM]/g; s/[n]/[nN]/g;
			s/[o]/[oO]/g; s/[ò]/[òÒ]/g; s/[ô]/[ôÔ]/g; s/[ó]/[óÓ]/g; s/[ö]/[öÖ]/g;
			s/[p]/[pP]/g; s/[q]/[qQ]/g; s/[r]/[rR]/g; s/[s]/[sS]/g; s/[t]/[tT]/g;
			s/[u]/[uU]/g; s/[ù]/[ùÙ]/g; s/[û]/[ûÛ]/g; s/[ú]/[úÚ]/g; s/[ü]/[üÜ]/g;
			s/[v]/[vV]/g; s/[w]/[wW]/g; s/[x]/[xX]/g; s/[y]/[yY]/g; s/[z]/[zZ]/g;
			s/[ç]/[çÇ]/g; s/[ñ]/[ñÑ]/g;
		' \
	)"'$/p' \
	| \
	sort \
	| \
	sed '/^\s*$/d; q;';
};

# ENV: _SHARED, _FLAGS_DEFAULT_MAIN
# $*: filepath
getCompileNotes() {

	local temporal='';
	temporal="$( findCompileNotesFile "$*" )" || return $?;
	[ -z "${temporal}" ] && return 0;

	local notes='';
	notes="$( cat "${temporal}" )";
	Error $? "loading notes from '${temporal}'" || return $?;

	local regexp='';
	local shared='';
	local loaded=0;

	# shared libraries
	regexp='\[\([lL][iI][bB]\([rR][aA][rR]\([yY]\|[iI][eE][sS]\)\|[sS]\?\)\?\(#[^]]*\)\?\)]';

	temporal="$( printf '%s' "${notes}" | sed -n 's/^'"${regexp}"'.*$/\1/; t_m; b; :_m; p; q;' )";
	if [ -n "${temporal}" ]; then

		_FLAGS_DEFAULT_MAIN='';

		loaded=1;

		# TODO: header stuff??

		shared="$( \
			printf '%s' "${notes}" \
			| \
			sed -n '
				/^'"${regexp}"'\s*/,/^\s*\[/{
					/^\s*\[/b;
					/^\s*\(#.*\)\?$/b;
					:_ok;
					p;
				};
			' \
		)";

		if [ -n "${shared}" ]; then
			_SHARED="$( printf '%s' "${shared}" | sed ':c;$!{N;bc;}; s/\n/ -l/g; s/^\s*/-l/; s/\s*$//; s/\s\s\+/ /g;' )";
		fi;
	fi;

	if [ -n "${loaded}" ]; then
		msgLoadedCompilationNotes "$*";
	fi;

	return 0;
};

# $*: filepath
findAnalog() {

	local temporal='';

	temporal="$( find -L "$( dirname "$*" )" -mindepth 1 -maxdepth 1 -type f )";
	Error $? "searching analog file to '$*'" || return $?;

	printf '%s' "${temporal}" \
	| \
	sed -n '/^\(.*\/\)\?'"$( \
		basename "$*" \
		| \
		sed '
			y/AEIOUÄÁÂÀËÉÊÈÏÍÎÌÖÓÔÒÜÚÛÙBCDFGHJKLMNPQRSTVWXYZÇÑ/aeiouäáâàëéêèïíîìöóôòüúûùbcdfghjklmnpqrstvwxyzçñ/;
			:_none;t_none;
			s/\.h$/\\.c/; t_ok;
			s/\.c$/\\.h/; t_ok;
			s/\.cnotes$/\\.c/; t_ok;
			:_ok;
			s/[a]/[aA]/g; s/[à]/[àÀ]/g; s/[â]/[âÂ]/g; s/[á]/[áÁ]/g; s/[ä]/[äÄ]/g;
			s/[b]/[bB]/g; s/[c]/[cC]/g; s/[d]/[dD]/g;
			s/[e]/[eE]/g; s/[è]/[èÈ]/g; s/[ê]/[êÊ]/g; s/[é]/[éÉ]/g; s/[ë]/[ëË]/g;
			s/[f]/[fF]/g; s/[g]/[gG]/g; s/[h]/[hH]/g;
			s/[i]/[iI]/g; s/[ì]/[ìÌ]/g; s/[î]/[îÎ]/g; s/[í]/[íÍ]/g; s/[ï]/[ïÏ]/g;
			s/[j]/[jJ]/g; s/[k]/[kK]/g; s/[l]/[lL]/g; s/[m]/[mM]/g; s/[n]/[nN]/g;
			s/[o]/[oO]/g; s/[ò]/[òÒ]/g; s/[ô]/[ôÔ]/g; s/[ó]/[óÓ]/g; s/[ö]/[öÖ]/g;
			s/[p]/[pP]/g; s/[q]/[qQ]/g; s/[r]/[rR]/g; s/[s]/[sS]/g; s/[t]/[tT]/g;
			s/[u]/[uU]/g; s/[ù]/[ùÙ]/g; s/[û]/[ûÛ]/g; s/[ú]/[úÚ]/g; s/[ü]/[üÜ]/g;
			s/[v]/[vV]/g; s/[w]/[wW]/g; s/[x]/[xX]/g; s/[y]/[yY]/g; s/[z]/[zZ]/g;
			s/[ç]/[çÇ]/g; s/[ñ]/[ñÑ]/g;
		' \
	)"'$/p' \
	| \
	sort \
	| \
	sed '/^\s*$/d; q;';
};

# $*: filepath
getIncludes_direct() {
	sed -n 's/^\s*#include\s\+"\([^"]\+\)"\s*$/\1/p' "$*";
	Error $? "obtaining includes from source code '$*'";
};

# $*: filepath
getIncludes() {

	local includes='';
	includes="$( getIncludes_direct "$*" )" || return $?;

	[ -z "${includes}" ] && return 0;

	local location="$( dirname "$*" )";

	local include='';
	local ifs="${IFS}";
	for include in $( printf '%s\n' "${includes}" ); do
		IFS="${ifs}";
		readlink -m "${location}/${include}";
	done;
	IFS="${ifs}";
};

findDlls() {

	[ -d "${DLL_FOLDER}" ] || return 0;

	local temporal='';
	temporal="$( find -L "${DLL_FOLDER}" -mindepth 1 -maxdepth 1 -type d )";
	Error $? "finding dll source code at '${DLL_FOLDER}'" || return $?;

	temporal="$( printf '%s' "${temporal}" | sed 's/^.*\///' )";

	local dlls='';
	local dll='';
	local ifs="${IFS}";
	IFS_toNewLine;
	for dll in $( printf '%s\n' "${temporal}" ); do
		IFS="${ifs}";

		# has a main file? (a source code "entrypoint")
		dll="$( findMainFilename "${DLL_FOLDER}/${dll}" )";
		if [ $? -eq 0 ]; then
			dlls="$( printf '%s\n%s' "${dlls}" "${dll}" )";
		fi;
	done;
	IFS="${ifs}";

	_DLLS="$( printf '%s' "${dlls}" | sed '/^\s*$/d' )";
};

# ENV: _CHECKED, _DLLS, _DEPENDENCIES, _LAST_MODIFICATION
# $*: filepath
fullInfoUpdate__inner() {

	local current="$*";
	local currentRegexp="$( text_toRexp "${current}" )";

	printf '%s' "${_CHECKED}" | sed -n '/^'"${currentRegexp}"'$/q33';
	[ $? -eq 33 ] && return 0;
	_CHECKED="$( printf '%s\n%s' "${_CHECKED}" "${current}" )";

	local temporal='';
	temporal="$( find "${current}" -printf '%Ts;%p\n' )";
	Error $? "obtaining last modification date of file '${current}'" || return $?;
	_LAST_MODIFICATION="$( printf '%s\n%s' "${_LAST_MODIFICATION}" "${temporal}" )";

	isHeader "${current}";
	local currentIsHeader=$?;

	local includes='';
	includes="$( getIncludes "${current}" )" || return $?;

	local added='';
	if [ -n "${includes}" ]; then
		local include='';
		local ifs="${IFS}";
		for include in $( printf '%s\n' "${includes}" ); do
			IFS="${ifs}";
			if isHeader "${include}"; then
				analog="$( findAnalog "${include}" )" || return $?;
				if [ -n "${analog}" ] && [ "${analog}" != "${current}" ]; then
					added="$( printf '%s\n%s' "${added}" "${analog}" )";
				fi;
			fi;
			fullInfoUpdate__inner "${include}" || return $?;
		done;
		IFS="${ifs}";
	fi;

	[ -n "${added}" ] && added="$( printf '%s' "${added}" | sed ':c;$!{N;bc;};s/\n/;/g;' )";
	local notes='';
	if [ ${currentIsHeader} -ne 0 ]; then
		notes="$( findCompileNotesFile "${current}" )" || return $?;
	fi;
	if [ -n "${notes}" ]; then
		temporal="$( find "${notes}" -printf '%Ts;%p\n' )";
		Error $? "obtaining last modification date of file '${notes}'" || return $?;
		_LAST_MODIFICATION="$( printf '%s\n%s' "${_LAST_MODIFICATION}" "${temporal}" )";

		notes=";${notes}";
	fi;

	analog="$( findAnalog "${current}" )" || return $?;
	if [ -n "${analog}" ]; then
		fullInfoUpdate__inner "${analog}" || return $?;
		if [ ${currentIsHeader} -ne 0 ]; then
			includes="$( \
				printf '%s\n%s' \
				"${includes}" \
				"$( \
					printf '%s' "${_DEPENDENCIES}" \
					| \
					sed -n 's/^'"$( text_toRexp "${analog}" )"';//; t_ok; b; :_ok; s/;/\n/g; p; q;' \
				)" \
			)";
		fi;
	fi;
	[ -n "${includes}" ] && includes="$( printf '%s' "${includes}" | sed '/^\s*$/d' | sort -u )";
	[ -n "${includes}" ] && includes=";$( printf '%s' "${includes}" | sed ':c;$!{N;bc;};s/\n/;/g;' )";

	analog="${notes}${added}${includes}";

	if [ -n "${analog}" ]; then
		_DEPENDENCIES="$( printf '%s\n%s' "${_DEPENDENCIES}" "${current}${analog}" )";
	fi;

	return 0;
};

# ENV: _DLLS, _DEPENDENCIES, _LAST_MODIFICATION
fullInfoUpdate() {

	local _CHECKED='';

	local source=''
	source="$( findMainFilename "${SRC_FOLDER}" )" || return $?;

	if [ -n "${_DLLS}" ]; then
		local dll='';
		local ifs="${IFS}";
		IFS_toNewLine;
		for dll in $( printf '%s\n' "${_DLLS}" ); do
			IFS="${ifs}";
			fullInfoUpdate__inner "${dll}" || return $?;
		done;
		IFS="${ifs}";
	fi;

	fullInfoUpdate__inner "${source}" || return $?;

	_LAST_MODIFICATION="$( printf '%s' "${_LAST_MODIFICATION}" | sed '/^\s*$/d' )";
	_DEPENDENCIES="$( printf '%s' "${_DEPENDENCIES}" | sed '/^\s*$/d' )";

	if [ ! -f "${LAST_MODIFICATION_FILE}" ]; then
		printf '' >> "${LAST_MODIFICATION_FILE}";
		Error $? "creating metadata file '${LAST_MODIFICATION_FILE}'" || return $?;
	fi;

	local saved='';
	saved="$( cat "${LAST_MODIFICATION_FILE}" )";
	Error $? "loading metadata from '${_LAST_MODIFICATION}'" || return $?;

	if [ -n "${saved}" ] && [ "${saved}" != "${_LAST_MODIFICATION}" ]; then
		#LAST_MODIFICATION="${saved}";
		local target='';
		local regexp='';
		local lastModification='';
		local temporal='';
		local ifs="${IFS}";
		IFS_toNewLine;
		for target in $( printf '%s\n' "${saved}" ); do
			IFS="${ifs}";

			# parametrizing, format: <lastupdate>;<filepath>
			lastModification="$( printf '%s' "${target}" | sed -n 's/^\([^;]*\);\(.*\)$/\1/p' )";
			target="$( printf '%s' "${target}" | sed -n 's/^\([^;]*\);\(.*\)$/\2/p' )";
			regexp="$( text_toRexp "${target}" )";

			temporal="$( printf '%s' "${_LAST_MODIFICATION}" | sed -n 's/^\([^;]*\);'"${regexp}"'$/\1/; t_ok; b; :_ok; p; q;' )";
			[ -z "${temporal}" ] && continue;

			if [ "${lastModification}" -lt "${temporal}" ]; then
				_LAST_MODIFICATION="$( printf '%s' "${_LAST_MODIFICATION}" | sed 's/^[^;]*;\('"${regexp}"'\)$/'"${lastModification}"';\1/;' )";
			fi;
		done;
		IFS="${ifs}";
	fi;

	if [ -n "${_LAST_MODIFICATION}" ]; then
		if [ -z "${saved}" ]; then
			_LAST_MODIFICATION="$( printf '%s' "${_LAST_MODIFICATION}" | sed 's/^[^;]*;/0;/' )";
		else
			_LAST_MODIFICATION="$( \
				printf '%s' "${_LAST_MODIFICATION}" \
				| \
				sed '
					/^[^;]*;\('"$( text_toRexp "$( printf '%s' "${saved}" | sed 's/^[^;]*;//' )" )"'\)$/b;
					s/^[^;]*;\([^;]*\)$/0;\1/;
				' \
			)";
		fi;
	fi;
};

# ENV: TO_COMPILE, DEPENDENCIES, LAST_MODIFICATION: updates...one per line, format: <lastupdate>;<filepath>
getCompileCandidates() {

	[ -z "${LAST_MODIFICATION}" ] && return 0;

	local output='';
	local lastModification='';
	local target='';
	local regexp='';
	local temporal='';
	local affected='';
	local ifs="${IFS}";

	# building list with timestamps and missing output files
	IFS_toNewLine;
	for target in $( printf '%s\n' "${LAST_MODIFICATION}" ); do
		IFS="${ifs}";

		affected='0';

		# parametrizing, format: <lastupdate>;<filepath>
		lastModification="$( printf '%s' "${target}" | sed -n 's/^\([^;]*\);\(.*\)$/\1/p' )";
		target="$( printf '%s' "${target}" | sed -n 's/^\([^;]*\);\(.*\)$/\2/p' )";

		temporal="$( find "${target}" -printf '%Ts' )";
		Error $? "obtaining last modification date of file '${target}'" || return $?;

		if [ ${temporal} -gt ${lastModification} ]; then
			affected='1';
			msgModificationDetected "${target}";
		else
			# not a header
			if ( ! isHeader "${target}" ) && ( ! isCNotes "${target}" ); then
				# no compiled file?
				temporal="${BIN_FOLDER}/$( getCompilationOutputSubPath "${target}" )";
				if [ ! -f "${temporal}" ]; then
					affected='1';
					msgMissingOutput "${target}" "${temporal}";
				fi;
			fi;
		fi;

		if [ ${affected} = '1' ]; then
			# adding target
			output="$( printf '%s\n%s' "${output}" "${target}" )";
		fi;
	done;
	IFS="${ifs}";

	temporal="$( printf '%s' "${output}" | sed '/^\s*$/d' | sort -u )";
	output='';

	# adding stuff affected because dependency
	if [ -n "${temporal}" ]; then
		local updated='';
		while true; do

			# get one target
			target="$( printf '%s' "${temporal}" | sed 'q' )";
			regexp="$( text_toRexp "${target}" )";

			if ( ! isHeader "${target}" ) && ( ! isCNotes "${target}" ); then
				output="$( printf '%s\n%s' "${output}" "${target}" )";
			else
				updateLastModificationTimestamp "${target}" || return $?;
			fi;

			# to updated list
			updated="$( printf '%s\n%s' "${updated}" "${target}" )";

			# removing from update targets
			temporal="$( printf '%s' "${temporal}" | sed '/^'"${regexp}"'$/d' )";

			# affected by dependency
			affected="$( printf '%s' "${DEPENDENCIES}" | sed -n 's/^\([^;]*\).*;'"${regexp}"'\(;.*\)\?$/\1/p' )";

			if [ -n "${affected}" ]; then
				msgAffectedByDependencies "${target}" "${affected}";
				affected="$( printf '%s' "${affected}" | sed '/^\('"$( text_toRexp "${updated}" )"'\)$/d' )";
			fi;
			if [ -n "${affected}" ]; then
				temporal="$( printf '%s\n%s' "${temporal}" "${affected}" | sed '/^\s*$/d' | sort -u )";
			fi;

			[ -z "${temporal}" ] && break;
		done;
	fi;

	TO_COMPILE="$( printf '%s' "${output}" | sed '/^\s*$/d' | sort -u )";
};

# ENV: _LIBS, _LIBS_CHECKED
# $*: filepath
findLibs_inner() {

	local current="$( readlink -m "$*" )";
	local currentRegexp="$( text_toRexp "${current}" )";

	printf '%s' "${_LIBS_CHECKED}" | sed -n '/^'"${currentRegexp}"'$/q33';
	[ $? -eq 33 ] && return 0;

	_LIBS_CHECKED="$( printf '%s\n%s' "${_LIBS_CHECKED}" "${current}" )";

	if ! isHeader "${current}"; then
		_LIBS="$( printf '%s\n%s' "${_LIBS}" "${current}" )";
	fi;

	local includes='';
	includes="$( getIncludes "${current}" )" || return $?;
	[ -z "${includes}" ] && return 0;

	local include='';
	local target='';
	local analog='';
	local location="$( dirname "${current}" )";
	local ifs="${IFS}";

	IFS_toNewLine;
	for include in $( printf '%s\n' "${includes}" ); do
		IFS="${ifs}";

		[ -f "${include}" ];
		Error $? "locating include file '${include}' (from: '${current}')" || return $?;

		findLibs_inner "${include}" || return $?;

		if isHeader "${include}"; then
			analog="$( findAnalog "${include}" )" || return $?;
			if [ -n "${analog}" ]; then
				findLibs_inner "${analog}" || return $?;
			fi;
		fi;
	done;
	IFS="${ifs}";
};

# ENV: _LIB
# $*: filepath
findLibs() {

	local current="$*";
	local currentRegexp="$( text_toRexp "${current}" )";

	local _LIBS_CHECKED='';

	findLibs_inner "${current}";

	_LIBS="$( printf '%s' "${_LIBS}" | sed '/^\s*$/d; /^'"${currentRegexp}"'$/d;' )";
	[ -z "${_LIBS}" ] && return 0;

	local subdir="$( \
		printf '%s' "${current}" \
		| \
		sed '
			s/^'"${SRC_FOLDER_REGEXP}"'\///;
			s/[^/]/./g;
			s/\.\+/../g;
		' \
	)";

	local output='';
	local ifs="${IFS}";
	local target='';
	IFS_toNewLine;
	for target in $( printf '%s\n' "${_LIBS}" ); do
		IFS="${ifs}";
		output="$( printf '%s\n%s' "${output}" "${subdir}/${BIN_SUBFOLDER}/$( printf '%s' "${target}" | sed 's/^'"${SRC_FOLDER_REGEXP}"'\///; s/\.[cC]/.o/;' )" )";
	done;
	IFS="${ifs}";

	_LIBS="$( printf '%s' "${output}" | sed '1d' )";
};

# $*: filepath
checkLibsDefined() {

	local _LIBS='';
	if [ "$*" = "${MAIN_SRC_FILE}" ] || isDll "$*"; then
		findLibs "$*";
	fi;
	[ -z "${_LIBS}" ] && return 0;

	cd "$( dirname "$*" )";

	local lib='';
	local ifs="${IFS}";
	for lib in $( printf '%s\n' "${_LIBS}" ); do
		IFS="${ifs}";

		[ -f "${lib}" ] || return $?;

	done;
	IFS="${ifs}";

	return 0;
};

# ENV: DLLS_regexp
# $*: filepath (not header)
compileTarget() {

	local current="$*";
	local currentRegexp="$( text_toRexp "${current}" )";
	local currentLocation="$( dirname "${current}" )";

	local includes='';
	includes="$( getIncludes "${current}" )" || return $?;

	local output="$( getCompilationOutputRelativePath "${current}" )";

	rm -rf "${output}";
	Error $? "removing previous files ${output}" || return $?;

	local location='';
	location="$( dirname "$( readlink -m "${currentLocation}/${output}" )" )";
	if [ ! -d "${location}" ]; then
		mkdir -p "${location}";
		Error $? "creating output location '${location}'" || return $?;
	fi;

	local _LIBS='';
	if [ "${current}" = "${MAIN_SRC_FILE}" ] || isDll "${current}"; then
		findLibs "${current}";
		if [ -n "${_LIBS}" ]; then
			_LIBS="-fpic $( printf '%s' "${_LIBS}" | sed ':c;$!{N;bc;};s/\n/ /g;' )";
		fi;
	fi;

	_SHARED='';
	_FLAGS_DEFAULT_MAIN="${FLAGS_DEFAULT_MAIN}";
	getCompileNotes "${current}" || return $?;

	local name="$( basename "${current}" )";

	location="${PWD}";
	cd "${currentLocation}";
	msgCd "${currentLocation}";

	CMD="${COMPILER} ${FLAGS} -o ${output}";

	# -c      : compile, linking stage simply is not done
	# -fpic   : position independant code (for shared libraries)
	# -shared : linkeable object
	# -l<lib> : search library to link
	# -L<dir> : where to search library

	# main source code
	if [ "${current}" = "${MAIN_SRC_FILE}" ]; then

		if [ -n "${MAIN_PID}" ]; then
			ps -p "${MAIN_PID}" 1>>/dev/null 2>>/dev/null;
			if [ $? -eq 0 ]; then
				msgCommand "kill '${MAIN_PID}'";
				kill "${MAIN_PID}";
				Error $? "terminating previous execution, pid ${MAIN_PID}" || return $?;
			fi;
		fi;

		CMD="${CMD} ${name} ${_FLAGS_DEFAULT_MAIN} ${_SHARED} ${_LIBS}";
	else
		if isDll "${current}"; then
			CMD="${CMD} ${name} ${_SHARED} -shared ${_LIBS}";
		else
			CMD="${CMD} -c ${name} -shared -fpic";
		fi;
	fi;

	msgCommand "${CMD}";
	${CMD};
	Error $? "while compiling '${current}'" || return $?;

	if [ "${current}" = "${MAIN_SRC_FILE}" ]; then
		"${output}" 1>"${RUN_STDOUT_PATH}" 2>"${RUN_STDERR_PATH}" &
		MAIN_PID=$!;
	fi;

	return 0;
};


### --- MISC

REXP_loadLines=':__REXP_loadLines__; $!{ N; b__REXP_loadLines__; };';
REXP_trim='s/^[ 	]*//; s/[ 	]*$//; s/[	 ]*\n[	 ]*/\n/g;';
REXP_removeWhiteLines='/^\s*$/d; :__REXP_removeWhiteLines__; s/\n[	 ]*\n/\n/g; t__REXP_removeWhiteLines__; s/^[\n	 ]\+//; s/[\n	 ]\+$//;';
REXP_simpleClean="${REXP_removeWhiteLines}${REXP_trim}";

text_toRexp() { printf '%s' "$*" | sed "${REXP_loadLines}${REXP_simpleClean}"' s/[][\/*.]/\\&/g; s/^\^/\\^/; s/\n\^/\n\\^/g; s/[$]$/[$]/; s/[$]\n/[$]\n/g; s/\n/\\|/g;'; };

text_removeDuplicatedLines() {
	printf '%s' "$*" \
	| \
	sed '
		'"${REXP_loadLines}"'

		s/^/\n\n/;
		s/$/\n\n/;
		s/\n/\n\n/g;

		:_loop;
		/\n\([^\n]\+\)\n\(.*\)\n\1\n/{
			s/\n\([^\n]\+\)\n\(.*\)\n\1\n/\n\1\n\n\2\n/g;
			b_loop;
		};

		s/^\n*//;
		s/\n*$//;
		s/\n\n\n*/\n/g;
	';
};

text_lineCount() { if [ -z "$*" ]; then printf '0'; return 0; fi; printf '%s' "$*" | sed '$!d; =; d;'; };

IFS_toNewLine() { IFS="$(printf '\nx')"; IFS="${IFS%x}"; };

tool_isDefined() { type "$*" 1>>/dev/null 2>>/dev/null; [ $? -eq 0 ] || return $?; };

printError() {
	local value="$1";
	shift 1;
	if [ -n "$*" ]; then
		printf 'Error[%s]: %s\n' "${value}" "$*" 1>&2;
	else
		printf 'Error[%s]\n' "${value}" 1>&2;
	fi;
};

Error() {
	[ $1 -eq 0 ] 2>>/dev/null && return 0;
	printError "$@";
	return $1;
};


### --- ENV

setEnv() {

	# do not expand paths
	set -f
	# error when using unset variables
	set -u

	## -- locales - lang

	LANG='en_US.UTF-8';
	LANGUAGE='';
	LC_CTYPE='en_US.UTF-8';
	LC_NUMERIC='en_US.UTF-8';
	LC_TIME='en_US.UTF-8';
	LC_COLLATE='en_US.UTF-8';
	LC_MONETARY='en_US.UTF-8';
	LC_MESSAGES='en_US.UTF-8';
	LC_PAPER='en_US.UTF-8';
	LC_NAME='en_US.UTF-8';
	LC_ADDRESS='en_US.UTF-8';
	LC_TELEPHONE='en_US.UTF-8';
	LC_MEASUREMENT='en_US.UTF-8';
	LC_IDENTIFICATION='en_US.UTF-8';
	LC_ALL='C';


	## -- system tools

	type sed 1>>/dev/null 2>>/dev/null;
	if [ $? -ne 0 ]; then
		printError 99 "tool 'sed' is cant not be found";
		return 1;
	fi;

	local tools="$( printf '%s' '

		# just a comment

		cat
		date
		ps
		kill

		sort

		readlink
		dirname
		basename

	' | sed ' /^\s*#/d; /^\s*$/d; s/^\s*//; s/\s*$//; ' )";

	if [ -n "${tools}" ]; then
		local not='';
		local tool='';
		local ifs="${IFS}";
		IFS_toNewLine;
		for tool in $( printf '%s\n' "${tools}" ); do
			IFS="${ifs}";
			if ! tool_isDefined "${tool}"; then
				not="$( printf '%s\n%s' "${not}" "${tool}" )";
			fi;
		done;
		IFS="${ifs}";

		if [ -n "${not}" ]; then
			Error 99 "tools not defined: $( printf '%s' "${not}" | sed ':c;$!{N;bc;};s/^\s*//;s/\n/, /g;' )" || return $?;
		fi;
	fi;


	## -- current instance info

	local procFile="/proc/$$/cmdline";

	SCRIPT_SHELL="$( sed ':c;$!{N;bc;}; s/\x0.*$//;' "${procFile}" )";
	Error $? "getting current shell info from pid file '${procFile}'" || return $?;

	SCRIPT_PATH="$( sed ':c;$!{N;bc;}; s/^[^\x0]*\x0//; s/\x0.*$//;' "${procFile}" )";
	Error $? "getting current execution path from pid file '${procFile}'" || return $?;
	SCRIPT_PATH="$( readlink -m "${SCRIPT_PATH}" )";

	SCRIPT_LOCATION="$( sed ':c;$!{N;bc;}; s/^[^\x0]*\x0//; s/\x0.*$//; s/\/[^/]*$//;' "${procFile}" )";
	Error $? "getting current location from pid file '${procFile}'" || return $?;
	SCRIPT_LOCATION="$( readlink -m "${SCRIPT_LOCATION}" )";

	SCRIPT_EXECUTABLE="$( sed ':c;$!{N;bc;}; s/^[^\x0]*\x0//; s/\x0.*$//; s/^.*\///;' "${procFile}" )";
	Error $? "getting current script name from pid file '${procFile}'" || return $?;


	## -- lock file

	SCRIPT_LOCK_FILE="${SCRIPT_LOCATION}/.$( printf '%s' "${SCRIPT_EXECUTABLE}" | sed 's/^\(.\+\)\.[^.]\+$/\1/' ).lock";

	if [ -f "${SCRIPT_LOCK_FILE}" ]; then

		local pid='';
		pid="$( sed 's/;.*$//' "${SCRIPT_LOCK_FILE}" )";
		Error $? "obtaining information from lockflie: '${SCRIPT_LOCK_FILE}'" || return $?;

		ps -p "${pid}" 1>>/dev/null 2>>/dev/null;
		[ $? -ne 0 ];
		Error $? "locked execution, file '${SCRIPT_LOCK_FILE}', pid ${pid}" || return $?;
	fi;

	printf '%s' "$$" > "${SCRIPT_LOCK_FILE}";
	Error $? "creating lock file: '${SCRIPT_LOCK_FILE}'" || return $?;

	TIMESTAMP_START="$( date +'%s.%N' )";

	MAIN_SRC_FILENAME_REGEXP='/^\(.*\/\)\?'"$( \
		printf '%s' "${MAIN_SRC_FILENAME}" \
		| \
		sed '
			y/AEIOUÄÁÂÀËÉÊÈÏÍÎÌÖÓÔÒÜÚÛÙBCDFGHJKLMNPQRSTVWXYZÇÑ/aeiouäáâàëéêèïíîìöóôòüúûùbcdfghjklmnpqrstvwxyzçñ/;
			s/[a]/[aA]/g; s/[à]/[àÀ]/g; s/[â]/[âÂ]/g; s/[á]/[áÁ]/g; s/[ä]/[äÄ]/g;
			s/[b]/[bB]/g; s/[c]/[cC]/g; s/[d]/[dD]/g;
			s/[e]/[eE]/g; s/[è]/[èÈ]/g; s/[ê]/[êÊ]/g; s/[é]/[éÉ]/g; s/[ë]/[ëË]/g;
			s/[f]/[fF]/g; s/[g]/[gG]/g; s/[h]/[hH]/g;
			s/[i]/[iI]/g; s/[ì]/[ìÌ]/g; s/[î]/[îÎ]/g; s/[í]/[íÍ]/g; s/[ï]/[ïÏ]/g;
			s/[j]/[jJ]/g; s/[k]/[kK]/g; s/[l]/[lL]/g; s/[m]/[mM]/g; s/[n]/[nN]/g;
			s/[o]/[oO]/g; s/[ò]/[òÒ]/g; s/[ô]/[ôÔ]/g; s/[ó]/[óÓ]/g; s/[ö]/[öÖ]/g;
			s/[p]/[pP]/g; s/[q]/[qQ]/g; s/[r]/[rR]/g; s/[s]/[sS]/g; s/[t]/[tT]/g;
			s/[u]/[uU]/g; s/[ù]/[ùÙ]/g; s/[û]/[ûÛ]/g; s/[ú]/[úÚ]/g; s/[ü]/[üÜ]/g;
			s/[v]/[vV]/g; s/[w]/[wW]/g; s/[x]/[xX]/g; s/[y]/[yY]/g; s/[z]/[zZ]/g;
			s/[ç]/[çÇ]/g; s/[ñ]/[ñÑ]/g;
		' \
	)"'$/p';

	BIN_FOLDER="$( readlink -m "${SCRIPT_LOCATION}/${BIN_SUBFOLDER}" )";
	SRC_FOLDER="$( readlink -m "${SCRIPT_LOCATION}/${SRC_SUBFOLDER}" )";
	SRC_FOLDER_REGEXP="$( text_toRexp "${SRC_FOLDER}" )";
	DLL_FOLDER="$( readlink -m "${SRC_FOLDER}/${DLL_SUBFOLDER}" )";

	RUN_STDOUT_PATH="${SCRIPT_LOCATION}/.$( printf '%s' "${SCRIPT_EXECUTABLE}" | sed 's/^\(.\+\)\.[^.]\+$/\1/' ).stdout";
	RUN_STDERR_PATH="${SCRIPT_LOCATION}/.$( printf '%s' "${SCRIPT_EXECUTABLE}" | sed 's/^\(.\+\)\.[^.]\+$/\1/' ).stderr";

	ROOT_FOLDERS_REGEXP="$( text_toRexp "$( printf '%s\n%s' "${BIN_FOLDER}" "${SRC_FOLDER}" )" )";

	LAST_MODIFICATION_FILE="${SCRIPT_LOCATION}/.$( printf '%s' "${SCRIPT_EXECUTABLE}" | sed 's/^\(.\+\)\.[^.]\+$/\1/' ).lastUpdates";

	return 0;
};

checkEnv() {

	if [ ! -d "${BIN_FOLDER}" ]; then
		mkdir -p "${BIN_FOLDER}";
		Error $? "while creating binaries folder '${BIN_FOLDER}'" || return $?;
	fi;

	if [ ! -d "${SRC_FOLDER}" ]; then
		Error $? "can not find source code folder '${SRC_FOLDER}'" || return $?;
	fi;

	if [ ! -d "${DLL_FOLDER}" ]; then
		mkdir -p "${BIN_FOLDER}";
		Error $? "while creating dlls source code subfolder '${DLL_FOLDER}'" || return $?;
	fi;

	MAIN_SRC_FILE="$( findMainFilename "${SRC_FOLDER}" )" || return $?;
	if [ ! -f "${MAIN_SRC_FILE}" ]; then
		Error $? "can not find main source code file '${MAIN_SRC_FILE}'" || return $?;
	fi;

	return 0;
};


### -- EXECUTION

main "$@";

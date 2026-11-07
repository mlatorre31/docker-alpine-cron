#!/bin/sh

src_dir=/etc/cron.d
spool_dir=/var/spool/cron/crontabs
tmp_file="$spool_dir/.cron-sync.tmp"

printf '%s\n' 'cron-sync: watching /etc/cron.d -> /var/spool/cron/crontabs every 60s'

while :; do
	changed=

	if ! mkdir -p "$spool_dir" 2>/dev/null; then
		printf 'cron-sync: error: mkdir %s failed\n' "$spool_dir"
	fi

	for src in "$src_dir"/*; do
		[ -f "$src" ] || continue
		name=${src##*/}
		case $name in
			cron.update|CRON_STRINGS) continue ;;
		esac
		dst="$spool_dir/$name"
		action=updated
		[ -e "$dst" ] || action=added

		if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
			if ! cp "$src" "$tmp_file" 2>/dev/null; then
				printf 'cron-sync: error: copy %s failed\n' "$name"
			elif ! chmod 0644 "$tmp_file" 2>/dev/null; then
				printf 'cron-sync: error: chmod %s failed\n' "$name"
			elif ! mv -f "$tmp_file" "$dst" 2>/dev/null; then
				printf 'cron-sync: error: move %s failed\n' "$name"
			else
				case $name in
					*[!A-Za-z0-9_-]*)
						printf 'cron-sync: warning: invalid name %s; notification skipped\n' "$name"
						;;
					*)
						changed="${changed}
$name"
						;;
				esac
				printf 'cron-sync: %s %s\n' "$action" "$name"
			fi
		fi
	done

	for dst in "$spool_dir"/*; do
		[ -f "$dst" ] || continue
		name=${dst##*/}
		case $name in
			cron.update|CRON_STRINGS|.cron-sync.tmp) continue ;;
		esac

		if [ ! -e "$src_dir/$name" ]; then
			if ! rm -f "$dst" 2>/dev/null; then
				printf 'cron-sync: error: remove %s failed\n' "$name"
			else
				case $name in
					*[!A-Za-z0-9_-]*)
						printf 'cron-sync: warning: invalid name %s; notification skipped\n' "$name"
						;;
					*)
						changed="${changed}
$name"
						;;
				esac
				printf 'cron-sync: removed %s\n' "$name"
			fi
		fi
	done

	if [ -n "$changed" ]; then
		old_ifs=$IFS
		IFS='
'
		set -f
		for name in $changed; do
			case $name in
				*[!A-Za-z0-9_-]*)
					printf 'cron-sync: warning: invalid name %s; notification skipped\n' "$name"
					;;
				*)
					if ! printf '%s\n' "$name" 2>/dev/null >> "$spool_dir/cron.update"; then
						printf 'cron-sync: error: notify %s failed\n' "$name"
					fi
					;;
			esac
		done
		set +f
		IFS=$old_ifs
	fi

	if ! sleep 60; then
		printf '%s\n' 'cron-sync: error: sleep failed'
	fi
done

select
	snapshot_id,
	source_uuid,
	source_version,
	source_type,
	convert_from(data, current_setting('server_encoding')) as data,
	convert_from(metadata, current_setting('server_encoding')) as metadata,
	created_at
from snapshots
order by created_at;
select
	event_id,
	stream_id,
	stream_version,
	event_type,
	correlation_id,
	convert_from(data, current_setting('server_encoding')) as data,
	convert_from(metadata, current_setting('server_encoding')) as metadata,
	created_at
from events
order by created_at desc;

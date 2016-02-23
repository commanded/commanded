select 
	event_id, 
	stream_id, 
	stream_version,
	event_type,
	correlation_id,
	convert_from(headers, current_setting('server_encoding')) as headers,
	convert_from(payload, current_setting('server_encoding')) as payload,
	created_at
from events
order by created_at desc;
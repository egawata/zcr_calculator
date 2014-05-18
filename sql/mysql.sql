CREATE TABLE site (
    id integer primary key,
    name varchar(255) not null
);

CREATE TABLE zcr (
    id integer primary key auto_increment,
    site_id integer not null,
    audio_id varchar(255) not null,
    zcr numeric(10,5) not null,
    unique key uniq_site_audio_id (site_id, audio_id)
);

INSERT INTO site (id, name) VALUES
(1, 'YouTube'),
(2, 'Terminal MP3 Download');



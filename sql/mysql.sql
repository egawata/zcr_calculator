CREATE TABLE site (
    id integer primary key,
    name varchar(255) not null
);

CREATE TABLE zcr (
  id int(11) NOT NULL AUTO_INCREMENT,
  site_id int(11) NOT NULL,
  audio_id varchar(255) NOT NULL,
  zcr decimal(10,5) NOT NULL,
  title varchar(255) NOT NULL,
  image_url varchar(255) DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_site_audio_id (site_id, audio_id),
  KEY idx_zcr (zcr)
);

INSERT INTO site (id, name) VALUES
(1, 'YouTube'),
(2, 'Terminal MP3 Download');



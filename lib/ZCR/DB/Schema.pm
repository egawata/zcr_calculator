package ZCR::DB::Schema;
use strict;
use warnings;
use utf8;

use Teng::Schema::Declare;

base_row_class 'ZCR::DB::Row';

table {
    name 'site';
    pk 'id';
    columns qw(id name);
};

table {
    name 'zcr';
    pk 'id';
    columns qw(id site_id audio_id zcr title image_url);
};


1;

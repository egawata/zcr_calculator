package ZCR::Web::Dispatcher;
use strict;
use warnings;
use utf8;
use Amon2::Web::Dispatcher::RouterBoom;
use Log::Minimal;
use Data::Dumper;
use File::Temp qw( tempfile tempdir );
use ZCR::Util;
use File::Spec;
use LWP::UserAgent;
use URI;
use JSON qw(decode_json);
use Encode qw(decode_utf8 encode_utf8);
use File::Path qw(remove_tree);
use Web::Scraper;


use constant SITE_ID_YOUTUBE    => 1;
use constant SITE_ID_TERMINAL   => 2;


any '/' => sub {
    my ($c) = @_;
    return $c->render('index.tt', {
    });
};


post '/get_zcr' => sub {
    my ($c) = @_;
    $c->db->{dbh}->do(q{SET NAMES UTF8});

    my $url = $c->req->param('url');
    debugf("URL: $url");

    my $res = {};
    if ( is_youtube_url($url) ) {
        $res = get_zcr_from_youtube($c, $url);
    }
    elsif ( is_terminal_url($url) ) {
        $res = get_zcr_from_terminal($c, $url);
    }

    return $c->render_json($res);
};


sub is_youtube_url {
    my ($url) = @_;

    return $url =~ m{\A\Qhttps://www.youtube.com/watch?v=\E} ? 1 : 0;
}


sub is_terminal_url {
    my ($url) = @_;

    return $url =~ m{\A\Qhttp://mp3-terminal.com/mp3_\E} ? 1 : 0;
}



sub get_zcr_from_youtube {
    my ($c, $url) = @_;

    my $video_id = extract_yt_video_id($url) or die;
    my %res = ();
    
    my ($row) = $c->db->search( zcr => { 
        site_id     => SITE_ID_YOUTUBE, 
        audio_id    => $video_id,
    });

    if ($row) {
        return {
            zcr         => $row->zcr,
            video_id    => $video_id,
            title       => decode_utf8($row->title),
            image_url   => $row->image_url,
            link_url    => get_link_url(SITE_ID_YOUTUBE, $video_id),
            resembles   => get_resemble_songs($c, $row->id, $row->zcr),
        };
    }

    my $tempdir = tempdir( DIR => '/tmp' );
    my $ret = system('youtube-dl', 
        '--audio-format', 'wav',
        '--extract-audio',
        '--output', File::Spec->catfile($tempdir, "%(id)s.%(ext).s"),
        "https://www.youtube.com/watch?v=$video_id"
    );

    if ( $ret == 0 ) {
        my ($wavfile) = <$tempdir/*.wav>;

        my $ua = LWP::UserAgent->new();
        my $http_res = $ua->get('https://www.googleapis.com/youtube/v3/videos'
            . '?id=' . $video_id
            . '&part=snippet'
            . '&key=' . $ENV{YT_API_KEY}
        );

        if ( $http_res->is_success ) {
            my $json = decode_json($http_res->content);
            my $snippet = $json->{items}->[0]->{snippet};

            %res = (
                zcr         => get_zcr($wavfile),
                video_id    => $video_id,
                image_url   => $snippet->{thumbnails}{default}{url},
                link_url    => 'https://www.youtube.com/watch?v=' . $video_id,
                title       => $snippet->{title},
                resembles   => get_resemble_songs($c, 0, $res{zcr}),
            );

            if ( $res{title} ) {
                $c->db->insert('zcr' => {
                    site_id     => SITE_ID_YOUTUBE,
                    audio_id    => $video_id,
                    zcr         => $res{zcr},
                    title       => $res{title},
                    image_url   => $res{image_url},
                });
            }

        }
        else {
            warnf("Failed to retrieve video info. " . $http_res->error_as_HTML);
        }
    }

    remove_tree($tempdir);

    return { %res };
}


sub extract_yt_video_id {
    my ($url) = @_;

    my $query = URI->new($url)->query;
    my @params = split '&', $query;
    my $video_id;
    for (@params) {
        if ( /^v=(.*)$/ ) {
            $video_id = $1;
            last;
        }
    }
    debugf("Video ID : $video_id");

    return $video_id;
}


sub get_zcr_from_terminal {
    my ($c, $url) = @_;

    my $ua = LWP::UserAgent->new();
    my $res = $ua->get($url);

    my %ret = ();
    if ($res->is_success) {
        my $content = $res->content;
        my $scraped = get_tm_scrape($content);
        debugf("Scraped data : " . Dumper($scraped));

        my $audio_id = $scraped->{id};
        my ($rec) = $c->db->search( zcr => {
            site_id     => SITE_ID_TERMINAL,
            audio_id    => $audio_id,
        });
        if ( $rec ) {
            return {
                zcr         => $rec->zcr,
                title       => decode_utf8($rec->title),
                image_url   => $rec->image_url,
                link_url    => get_link_url(SITE_ID_TERMINAL, $audio_id),
                resembles   => get_resemble_songs($c, $rec->id, $rec->zcr),
            };
        }

        my $mp3_url = $scraped->{mp3_url};
        (undef, my $mp3_file) = tempfile( 'XXXXXXXX', SUFFIX => '.mp3', DIR => '/tmp', OPEN => 0 );
        (undef, my $wav_file) = tempfile( 'XXXXXXXX', SUFFIX => '.mp3', DIR => '/tmp', OPEN => 0 );
        debugf("MP3 file : $mp3_file");

        system('wget', '-O', $mp3_file, $mp3_url) == 0 
            or die "Failed to wget mp3 file from $mp3_url";
        system('lame', '--decode', $mp3_file, $wav_file) == 0
            or die "Failed to convert $mp3_file to $wav_file";

        my $zcr = get_zcr($wav_file);
        unlink $mp3_file;
        unlink $wav_file;

        %ret = (
            zcr         => $zcr,
            title       => decode_utf8($scraped->{title}),
            image_url   => $scraped->{image_url},
            link_url    => get_link_url(SITE_ID_TERMINAL, $audio_id),
            resembles   => get_resemble_songs($c, 0, $zcr),
        );

        if ( defined($ret{title}) ) {
            $c->db->insert( zcr => {
                site_id         => SITE_ID_TERMINAL,
                audio_id        => $audio_id,
                zcr             => $zcr,
                title           => $ret{title},
                image_url       => $ret{image_url},
            });
        }
    }

    return { %ret };
}


sub get_tm_scrape {
    my ($content) = @_;

    my $scraper = scraper {
        process '#preview_id',  'id' => 'TEXT';
        process '#mp3_url',     'mp3_url' => 'TEXT';
        process '#ext-code',    'title' => 'TEXT';
        process '#tpc_track_jacket_img', 'image_url' => '@src';
    };

    my $res = $scraper->scrape($content);

    return $res;
}


#  ZCRが近い楽曲を検索する。
#  ID が全く同じ曲は除外したいので、元の曲の zcr.id を $id で指定する。
#  現時点でIDがない場合は 0 を指定しておく。
sub get_resemble_songs {
    my ($c, $id, $zcr) = @_;

    my @songs = ();
    my @rows = $c->db->search_by_sql(q{
        SELECT *
          FROM zcr
         WHERE id != ?
      ORDER BY abs(? - zcr)
         LIMIT ?
    }, [ $id, $zcr, 5 ]);

    for my $row (@rows) {
        push @songs, {
            zcr         => $row->zcr,
            video_id    => $row->audio_id,
            image_url   => $row->image_url,
            link_url    => get_link_url($row->site_id, $row->audio_id),
            title       => decode_utf8($row->title),
        };
    }

    return [@songs];
}


sub get_link_url {
    my ($site_id, $audio_id) = @_;

    if ( $site_id == SITE_ID_YOUTUBE ) {
        return "https://www.youtube.com/watch?v=$audio_id";
    }
    elsif ( $site_id == SITE_ID_TERMINAL ) {
        return "http://mp3-terminal.com/s/$audio_id/";
    }
    
    return undef;
}




1;

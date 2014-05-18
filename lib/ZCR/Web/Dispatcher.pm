package ZCR::Web::Dispatcher;
use strict;
use warnings;
use utf8;
use Amon2::Web::Dispatcher::RouterBoom;
use Log::Minimal;
use Data::Dumper;
use File::Temp qw(tempdir);
use ZCR::Util;
use File::Spec;
use LWP::UserAgent;
use URI;
use JSON qw(decode_json);
use Encode qw(decode_utf8 encode_utf8);
use File::Path qw(remove_tree);

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

    my $res;
    if ( is_youtube_url($url) ) {
        $res = get_zcr_from_youtube($c, $url);
    }

    return $c->render_json($res);
};


sub is_youtube_url {
    my ($url) = @_;

    return $url =~ m{\A\Qhttps://www.youtube.com/watch?v=\E} ? 1 : 0;
}


sub get_zcr_from_youtube {
    my ($c, $url) = @_;

    my $video_id = extract_video_id($url) or die;
    
    my ($row) = $c->db->search( zcr => { site_id => 1, audio_id => $video_id } );
    if ( $row ) {
        return {
            zcr         => $row->zcr,
            video_id    => $video_id,
            title       => decode_utf8($row->title),
            image_url   => $row->image_url,
            link_url    => 'https://www.youtube.com/watch?v=' . $video_id,
            resembles   => get_resemble_songs($c, $row->zcr),
        };
    }

    my $tempdir = tempdir( DIR => '/tmp' );
    my $ret = system('youtube-dl', 
        '--audio-format', 'wav',
        '--extract-audio',
        '--output', File::Spec->catfile($tempdir, "%(id)s.%(ext).s"),
        "https://www.youtube.com/watch?v=$video_id"
    );

    my %res = ();

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

            $res{zcr} = get_zcr($wavfile);
            $res{video_id} = $video_id;
            $res{image_url} = $snippet->{thumbnails}{default}{url};
            $res{link_url}  = 'https://www.youtube.com/watch?v=' . $video_id;
            $res{title}     = $snippet->{title};
            $res{resembles} = get_resemble_songs($c, $res{zcr});

            $c->db->insert('zcr' => {
                site_id     => 1,
                audio_id    => $video_id,
                zcr         => $res{zcr},
                title       => $res{title},
                image_url   => $res{image_url},
            });

        }
        else {
            warnf("Failed to retrieve video info. " . $http_res->error_as_HTML);
        }
    }

    remove_tree($tempdir);

    return { %res };
}


sub extract_video_id {
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


sub get_resemble_songs {
    return [];
}

1;

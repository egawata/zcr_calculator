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


any '/' => sub {
    my ($c) = @_;
    return $c->render('index.tt', {
    });
};

post '/get_zcr' => sub {
    my ($c) = @_;

    my $url = $c->req->param('url');
    debugf("URL: $url");

    my $res;
    if ( is_youtube_url($url) ) {
        $res = get_zcr_from_youtube($url);
    }

    return $c->render_json($res);
};


sub is_youtube_url {
    my ($url) = @_;

    return $url =~ m{\A\Qhttps://www.youtube.com/watch?v=\E} ? 1 : 0;
}


sub get_zcr_from_youtube {
    my ($url) = @_;

    my $video_id = extract_video_id($url) or die;
    
    my $zcr;
    my $tempdir = tempdir( DIR => '/tmp' );
    my $ret = system('youtube-dl', 
        '--audio-format', 'wav',
        '--extract-audio',
        '--output', File::Spec->catfile($tempdir, "%(id)s.%(ext).s"),
        $url
    );

    my %res = ();

    if ( $ret == 0 ) {
        my ($wavfile) = <$tempdir/*.wav>;
        $res{zcr} = get_zcr($wavfile);

        my $ua = LWP::UserAgent->new();
        my $res = $ua->get('https://www.googleapis.com/youtube/v3/videos'
            . '?id=' . $video_id
            . '&part=snippet'
            . '&key=' . $ENV{YT_API_KEY}
        );
        if ( $res->is_success ) {
            my $json = decode_json($res->content);
            my $snippet = $json->{items}->[0]->{snippet};

            $res{image_url} = $snippet->{thumbnails}{default}{url};
            $res{title}     = $snippet->{title};
        }
        else {
            warnf("Failed to retrieve video info. " . $res->error_as_HTML);
        }
    }

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


1;

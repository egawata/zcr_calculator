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


any '/' => sub {
    my ($c) = @_;
    return $c->render('index.tt', {
    });
};

post '/get_zcr' => sub {
    my ($c) = @_;

    my $url = $c->req->param('url');
    debugf("URL: $url");

    my $zcr;
    if ( is_youtube_url($url) ) {
        $zcr = get_zcr_from_youtube($url);
    }

    return $c->render_json({ zcr => $zcr });
};


sub is_youtube_url {
    my ($url) = @_;

    return $url =~ m{\A\Qhttps://www.youtube.com/watch?v=\E} ? 1 : 0;
}


sub get_zcr_from_youtube {
    my ($url) = @_;
    
    my $zcr;
    my $tempdir = tempdir( DIR => '/tmp' );
    my $ret = system('youtube-dl', 
        '--audio-format', 'wav',
        '--extract-audio',
        '--output', q{'} . File::Spec->catfile($tempdir, "%(id)s.%(ext).s") . q{'},
        $url
    );

    if ( $ret == 0 ) {
        my ($wavfile) = <$tempdir/*.wav>;
        $zcr = get_zcr($wavfile);
    }

    return $zcr;
}


1;

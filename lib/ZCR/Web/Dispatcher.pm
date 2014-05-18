package ZCR::Web::Dispatcher;
use strict;
use warnings;
use utf8;
use Amon2::Web::Dispatcher::RouterBoom;
use Log::Minimal;
use Data::Dumper;

any '/' => sub {
    my ($c) = @_;
    return $c->render('index.tt', {
    });
};

post '/get_zcr' => sub {
    my ($c) = @_;

    my $url = $c->req->param('url');
    debugf("URL: $url");

    return $c->render_json({ zcr => 1.45 });
};

1;

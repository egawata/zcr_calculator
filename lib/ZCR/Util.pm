package ZCR::Util;

use base qw(Exporter);
use Audio::Wav;
use List::Util qw(sum);


our @EXPORT = qw(get_zcr);


sub get_zcr {
    my ($wavfile) = @_;

    my $wav = new Audio::Wav();
    my $read = $wav->read($wavfile);
    
    my $details = $read->details();
    my $sample_rate = $details->{sample_rate};
    my $length_sec  = $details->{length};
    my $num_samples = $length_sec * $sample_rate;
    my $num_channels = $details->{channels};

    my $start  = int( ($length_sec / 2 - 15) * $sample_rate );
    my $length = $sample_rate * 30;

    $start > 0 or $start = 0;
    $start + $length < $num_samples
        or $length = $num_samples - $start;

    $read->move_to_sample($start);

    my $prev_amp = 0;
    my $zero_count = 0;
    for ( 1 .. $length - 1 ) {
        my @channels = $read->read();
        defined( $channels[0] )
            or die "Failed to retrieve sample at $_\n";
        my $amp = sum(@channels) / $num_channels;
        $prev_amp * $amp < 0 and $zero_count++;
        $prev_amp = $amp;
    }

    #  1ms あたりの ZCR
    my $zcr = $zero_count / ($length / $sample_rate * 1000);

    return $zcr;
}


1;



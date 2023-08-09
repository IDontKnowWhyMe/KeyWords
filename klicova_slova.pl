#!/usr/bin/perl

use strict;
use warnings;
use Lingua::Stem::Snowball;
use Getopt::Long;
use JSON;

# Parse command line options
my $stopwords_dir = "stopwords";
my $lang = "en";
my $num_keywords = 10;
my $output_format = "text";
my $help = 0;
GetOptions(
    'stopwords=s' => \$stopwords_dir,
    'lang=s' => \$lang,
    'num_keywords=i' => \$num_keywords,
    'output_format=s' => \$output_format,
    'help' => \$help,
) or die "Error parsing command line options\n";

# Check for help option
if ($help) {
    print "Usage: perl klicova_slova.pl [options]\n";
    print "Extracts and ranks keywords from text provided on standard input.\n";
    print "Options:\n";
    print "  --stopwords DIR      Path to stop words folder (default: stopwords)\n";
    print "  --lang LANG           Language for stemming and stop words (default: en)\n";
    print "  --num_keywords NUM    Number of keywords to output (default: 10)\n";
    print "  --output_format FMT   Output format (text, json, csv) (default: text)\n";
    print "  --help                Show this help message\n";
    exit;
}

# Load stop words from file
my $stopwords_file = "$stopwords_dir/$lang.txt";
my @stopwords;
if (-e $stopwords_file) {
    open(my $fh, "<", $stopwords_file) or die "Cannot open file $stopwords_file: $!";
    while (my $line = <$fh>) {
        chomp $line;
        push @stopwords, $line;
    }
    close($fh);
} else {
    warn "Warning: Stop words file '$stopwords_file' not found. Proceeding without stop words.\n";
}

# Initialize stemmer
my %lang_map = (
    'sk' => 'sk',
    'cz' => 'cs',
    'en' => 'en',
);
my $stemmer_lang = $lang_map{$lang} || 'en';
my $stemmer = Lingua::Stem::Snowball->new( lang => $stemmer_lang );

# Load input text from standard input
my $text = do { local $/; <STDIN> };
if (!defined $text || length($text) == 0) {
    die "Error: No input provided on standard input\n";
}

# Tokenize text into individual words
my @words = split /\s+/, $text;

# Remove punctuation and convert to lowercase
foreach my $word (@words) {
    $word =~ s/[[:punct:]]//g;
    $word = lc $word;
}

# Remove stop words and apply stemming
@words = grep { my $w = $_; !grep { $_ eq $w } @stopwords } @words;
foreach my $word (@words) {
    $word = $stemmer->stem($word);
}

# Calculate word frequency
my %word_freq;
foreach my $word (@words) {
    $word_freq{$word}++;
}

# Calculate word importance using TextRank algorithm
my %scores;
my $damping_factor = 0.85;
my $max_iterations = 50;
my $convergence_threshold = 0.0001;
my $num_words = scalar @words;

foreach my $word (keys %word_freq) {
    $scores{$word} = 1;
}

for (my $i = 0; $i < $max_iterations; $i++) {
    my %new_scores;

    foreach my $word (keys %word_freq) {
        $new_scores{$word} = (1 - $damping_factor) / $num_words;

        foreach my $adj_word (keys %word_freq) {
            next if $word eq $adj_word;

            my $adj_frequency = $word_freq{$adj_word};
            my $adj_links = $word_freq{$word};

            if ($adj_frequency > 0) {
                $new_scores{$word} += ($damping_factor * $scores{$adj_word} * $adj_links) / $adj_frequency;
            }
        }
    }

    my $max_diff = 0;
    foreach my $word (keys %scores) {
        my $diff = abs($scores{$word} - $new_scores{$word});
        if ($diff > $max_diff) {
            $max_diff = $diff;
        }
    }

    last if $max_diff < $convergence_threshold;

    %scores = %new_scores;
}

# Normalize scores
my $max_score = (sort { $b <=> $a } values %scores)[0];
foreach my $word (keys %scores) {
    $scores{$word} /= $max_score;
}

# Sort keywords by importance
my @sorted_words = sort { $scores{$b} <=> $scores{$a} } keys %scores;

# Output keywords to standard output
if ($output_format eq "json") {
    my @output_data;
    foreach my $word (@sorted_words[0..$num_keywords-1]) {
        if (defined $word) {
            push @output_data, { word => $word, score => $scores{$word} };
        }
    }
    print to_json(\@output_data, { pretty => 1 });
} elsif ($output_format eq "csv") {
    print "word,score\n";
    foreach my $word (@sorted_words[0..$num_keywords-1]) {
        if (defined $word) {
            print "$word,$scores{$word}\n";
        }
    }
} else {
    foreach my $word (@sorted_words[0..$num_keywords-1]) {
        if (defined $word) {
            print "$word\n";
        }
    }
}

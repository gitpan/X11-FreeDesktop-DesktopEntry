# $Id: DesktopEntry.pm,v 1.1.1.1 2005/01/01 19:29:35 jodrell Exp $
# Copyright (c) 2005 Gavin Brown. All rights reserved. This program is
# free software; you can redistribute it and/or modify it under the same
# terms as Perl itself. 
package X11::FreeDesktop::DesktopEntry;
use Carp;
use vars qw($VERSION $DEFAULT_GROUP $DEFAULT_LOCALE @REQUIRED $VERBOSE $SILENT);
use utf8;
use strict;

our $VERSION		= '0.01';
our $DEFAULT_GROUP	= 'Desktop Entry';
our $DEFAULT_LOCALE	= 'C';
our @REQUIRED		= qw(Encoding Name Type);
our $VERBOSE		= 0;
our $SILENT		= 0;

=pod

=head1 NAME

X11::FreeDesktop::DesktopEntry - an interface to Freedesktop.org .desktop files.

=head1 SYNOPSIS

	use X11::FreeDesktop::DesktopEntry;

	my $entry = X11::FreeDesktop::DesktopEntry->new_from_data($data);

	print $entry->get_value('Name');

=head1 DESCRIPTION

This module provides an object-oriented interface to files that comply with the
Freedesktop.org desktop entry specification. You can query the file for
available values and also get locale information as well.

=head1 CONSTRUCTOR

	my $entry = X11::FreeDesktop::DesktopEntry->new_from_data($data);

If there is an error reading or parsing the file, the constructor will
C<carp()> and return an undefined value.

=cut

sub new {
	my ($package, $data) = @_;
	my $self = { _raw => $data };
	bless($self, $package);
	if ($self->{_raw} eq '') {
		carp("got no data for $self->{uri}") unless ($SILENT == 1);
		return undef;
	}
	return undef unless ($self->parse);
	return $self;
}

sub parse {
	my $self = shift;
	my @lines = split(/[\r\n]/, $self->{_raw});
	my ($current_group, $last_key);
	for (my $i = 0 ; $i < scalar(@lines) ; $i++) {
		chomp(my $line = $lines[$i]);

		if ($line =~ /^[\s\t\r\n]*$/) {
			# ignore whitespace:
			next;

		} elsif ($line =~ /^\s*\#(.+)$/) {
			# the spec requires that we be able to preserve comments, so
			# we need to note the position that the comment occurred at, relative
			# to the current group and last key:
			push(@{$self->{comments}}, {
				text		=> $1,
				group		=> (defined($current_group) ? $current_group : '_root'),
				last_key	=> $last_key,
			});
		
		} elsif ($line =~ /^\[([^\[]+)\]/) {
			# defines a new group:
			$current_group = $1;
			$self->{data}->{$current_group} = {};

		} elsif ($current_group ne '') {
			# got a key=value pair:
			my ($key, $value) = split(/\s*=\s*/, $line, 2);
			$last_key = $key;
			my $locale = $DEFAULT_LOCALE;

			# check for the Key[postfix] format:
			if ($key =~ /\[([^\[]+)\]$/) {
				$locale = $1;
				$key =~ s/\[$locale\]$//;
			}
			if (defined($self->{data}->{$current_group}->{$key}->{$locale})) {
				carp(sprintf(
					'Parse error on %s line %s: value already exists for \'%s\' in \'%s\', skipping later entry',
					$self->{uri},
					$i+1,
					$last_key,
					$current_group,
				)) if ($VERBOSE == 1);

			} else {
				$self->{data}->{$current_group}->{$key}->{$locale} = $value;

			}

		} else {
			# an error:
			carp(sprintf('Parse error on %s line %s: no group name defined', $self->{uri}, $i+1)) unless ($SILENT == 1);
			return undef;
		}
	}
	return 1;
}

=pod

=head1 METHODS

	$entry->is_valid($locale);

Returns a true or false valid depending on whether the required keys exist for
the given C<$locale>. A list of the required keys can be found in the
Freedesktop.org specification. If C<$locale> is omitted, it will default to
'C<C>'.

=cut

sub is_valid {
	my ($self, $locale) = @_;
	$locale	= (defined($locale) ? $locale : $DEFAULT_LOCALE);

	foreach my $key (@REQUIRED) {
		if (!defined($self->get_value($key, $DEFAULT_GROUP, $locale))) {
			return undef;
		}

	}
	return 1;
}

=pod
	my @groups = $entry->groups;

This returns an array of scalars containing the I<group names> included in the
file. Groups are defined by a line like the following in the file itself:

	[Desktop Entry]

A valid desktop entry file will always have one of these, at the top.

=cut

sub groups {
	return keys(%{$_[0]->{data}});
}

=pod

	$entry->has_group($group);

Returns true or false depending on whether the file has a section with the name
of C<$group>.

=cut

sub has_group {
	return defined($_[0]->{data}->{$_[1]});
}

=pod

	my @keys = $entry->keys($group, $locale);

Returns an array of the available keys in C<$group> and the C<$locale> locale.
Both these values revert to defaults if they're undefined. When C<$locale> is
defined, the array will be folded in with the keys from 'C<C>', since locales
inherit keys from the default locale. See the C<get_value()> method for
another example of this inheritance.

=cut

sub keys {
	my ($self, $group, $locale) = @_;
	$group	= (defined($group) ? $group : $DEFAULT_GROUP);
	my %keys;
	foreach my $key (keys(%{$self->{data}->{$group}})) {
		# add the key if $locale is defined and a value exists for that locale, or if $locale isn't defined:
		$keys{$key} ++ if ((defined($locale) && defined($self->{data}->{$group}->{$key}->{$locale})) || !defined($locale));
	}
	if ($locale ne $DEFAULT_LOCALE) {
		# fold in the keys for the default locale:
		foreach my $key ($self->keys($group, $DEFAULT_LOCALE)) {
			$keys{$key}++;
		}
	}
	return sort(keys(%keys));
}

=pod

	$entry->has_key($key, $group);

Returns true or false depending on whether the file has a key with the name of
C<$key> in the C<$group> section. If C<$group> is omitted, then the default
group (C<'Desktop Entry'>) will be used.

=cut

sub has_key {
	return defined($_[0]->{data}->{defined($_[2]) ? $_[2] : $DEFAULT_GROUP}->{$_[1]});
}

=pod

	my $string = $entry->get_value($key, $group, $locale);

Returns the value of the key named by C<$key>. C<$group> is optional, and will
be set to the default if omitted (see above). C<$locale> is also optional, and
defines the locale for the string (defaults to 'C<C>' if omitted). If the
requested key does not exist for a non-default C<$locale> of the form C<xx_YY>,
then the module will search for a value for the C<xx> locale. If nothing is
found, this method will attempt to return the value for the 'C<C>' locale. If
this value does not exist, this method will return undef.

=cut

sub get_value {
	my ($self, $key, $group, $locale) = @_;
	$group	= (defined($group) ? $group : $DEFAULT_GROUP);
	$locale	= (defined($locale) ? $locale : $DEFAULT_LOCALE);

	($locale, undef) = split(/\./, $locale, 2); # in case locale is of the form xx_YY.UTF-8

	my $rval;
	if (!defined($self->{data}->{$group}->{$key}->{$locale})) {
		if ($locale =~ /^[a-z]{2}_[A-Z]{2}$/) {
			my ($base, undef) = split(/_/, $locale, 2);
			$rval = $self->get_value($key, $group, $base);

		} else {
			$rval = ($locale eq $DEFAULT_LOCALE ? undef : $self->get_value($key, $group, $DEFAULT_LOCALE));

		}

	} else {
		$rval = $self->{data}->{$group}->{$key}->{$locale};

	}

	utf8::decode($rval);
	return $rval;
}

=pod

	my @locales = $entry->locales($key, $group);

Returns an array of strings naming all the available locales for the given
C<$key>. If C<$key> or C<$group> don't exist in the file, this method will
C<carp()> and return undef. There should always be at least one locale in the
returned array - the default locale, 'C<C>'.

=cut

sub locales {
	my ($self, $key, $group) = @_;
	$group	= (defined($group) ? $group : $DEFAULT_GROUP);

	if (!$self->has_group($group)) {
		carp(sprintf('get_value(): no \'%s\' group found', $group)) if ($VERBOSE == 1);
		return undef;

	} elsif (!$self->has_key($key, $group)) {
		carp(sprintf('get_value(): no \'%s\' key found in \'%s\'', $key, $group)) if ($VERBOSE == 1);
		return undef;

	} else {
		return keys(%{$self->{data}->{$group}->{$key}});

	}
}

=pod

=head1 CONVENIENCE METHODS

	my $name		= $entry->Name($locale);
	my $generic_name	= $entry->GenericName($locale);
	my $comment		= $entry->Comment($locale);
	my $type		= $entry->Type($locale);
	my $icon		= $entry->Icon($locale);
	my $exec		= $entry->Exec($locale);
	my $url			= $entry->URL($locale);
	my $startup_notify	= $entry->StartupNotify($locale);

These methods are shortcuts for the mostly commonly accessed fields from a
desktop entry file. If undefined, $locale reverts to the default.

=cut

sub Name		{ $_[0]->get_value('Name',		$DEFAULT_GROUP, $_[1]) }
sub GenericName		{ $_[0]->get_value('GenericName',	$DEFAULT_GROUP, $_[1]) }
sub Comment		{ $_[0]->get_value('Comment',		$DEFAULT_GROUP, $_[1]) }
sub Type		{ $_[0]->get_value('Type',		$DEFAULT_GROUP, $_[1]) }
sub Icon		{ $_[0]->get_value('Icon',		$DEFAULT_GROUP, $_[1]) }
sub Exec		{ $_[0]->get_value('Exec',		$DEFAULT_GROUP, $_[1]) }
sub URL			{ $_[0]->get_value('URL',		$DEFAULT_GROUP, $_[1]) }
sub StartupNotify	{ return ($_[0]->get_value('StartupNotify', $DEFAULT_GROUP, $_[1]) eq 'true' ? 1 : undef) }

=pod

=head1 NOTES

Please note that according to the Freedesktop.org spec, key names are case-sensitive.

=head1 TODO

=over

=item * Support modification of values, and writing back.

=back

=head1 SEE ALSO

The Freedesktop.org Desktop Entry Specification at L<http://www.freedesktop.org/Standards/desktop-entry-spec>.

=head1 AUTHOR

Gavin Brown E<lt>gavin.brown@uk.comE<gt>.

=head1 COPYRIGHT

Copyright (c) 2005 Gavin Brown. This program is free software, you can use it and/or modify it under the same terms as Perl itself.

=cut

1;

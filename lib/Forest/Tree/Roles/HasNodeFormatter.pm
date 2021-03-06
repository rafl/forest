package Forest::Tree::Roles::HasNodeFormatter;
use Moose::Role;

our $VERSION   = '0.04';
our $AUTHORITY = 'cpan:STEVAN';

has 'node_formatter' => (
    is      => 'rw', 
    isa     => 'CodeRef',
    lazy    => 1,
    default => sub { 
        sub { (shift)->node  || 'undef' } 
    }
);

sub format_node {
    my $self = shift;
    $self->node_formatter->(@_)
}

no Moose::Role; 1;

__END__

=pod

=head1 NAME

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS 

=over 4

=item B<>

=back

=head1 BUGS

All complex software has bugs lurking in it, and this module is no 
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan.little@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2008 Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

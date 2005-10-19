package Tree::Persist::DB::SelfReferential;

use strict;
use warnings;

use base qw( Tree::Persist::DB );

use Scalar::Util qw( blessed refaddr );

use Tree;

sub new {
    my $class = shift;
    my ($opts) = @_;

    my $self = $class->SUPER::new( $opts );

    $self->{_id} = $opts->{id};

    $self->{_id_col} = 'id';
    $self->{_parent_id_col} = 'parent_id';
    $self->{_value_col} = 'value';
    $self->{_class_col} = 'class';

    return $self;
}

sub reload {
    my $self = shift;

    my %sql = $self->_build_sql;

    my $sth = $self->{_dbh}->prepare( $sql{ fetch } );
    $sth->execute( $self->{_id} );

    my ($id, $parent, $class, $value) = $sth->fetchrow_array();

    $sth->finish;

    my $tree = $class->new( $value );

    $self->{_mapping} ||= {};
    $self->{_mapping}{$id} = $tree;
    $tree->meta->{refaddr $self}{id} = $id;

    my @parents = ( $id );
    while ( my $parent_id = shift @parents ) {
        my $sth_child = $self->{_dbh}->prepare( $sql{ fetch_children } );
        $sth_child->execute( $parent_id );

        my $parent = $self->{_mapping}{ $parent_id };

        $sth_child->bind_columns( \my ($id, $class, $value) );

        while ($sth_child->fetch) {
            my $node = $class->new( $value );
            $parent->add_child( $node );
            push @parents, $id;
            $self->{_mapping}{$id} = $node;
            $node->meta->{refaddr $self}{id} = $id;
        }

        $sth_child->finish;
    }

    $self->set_tree( $tree );

    return $self;
}

sub _create {
    my $self = shift;
    my $tree = shift || $self->tree;

    my $dbh = $self->{_dbh};
    my %sql = $self->_build_sql;

    my $next_id = do {
        my $sth = $dbh->prepare( $sql{next_id} );
        $sth->execute;
        $sth->fetchrow_array;
    };

    my $root_id = $tree->meta->{refaddr $self}{id} ||= $next_id++;

    my $sth = $dbh->prepare( $sql{create_node} );
    my $parent_id = $tree->parent
        ? $tree->parent->meta->{refaddr $self}{id}
        : undef;
    $sth->execute(
        $root_id, $parent_id, blessed($tree), $tree->value,
    );

    $self->{_mapping} ||= {};
    $self->{_mapping}{ $root_id } = $tree;

    my @parents = ( $root_id );
    while ( my $parent_id = shift @parents ) {
        my $parent = $self->{_mapping}{$parent_id};

        foreach my $child ($parent->children) {
            my $child_id = $child->meta->{refaddr $self}{id} ||= $next_id++;
            $sth->execute(
                $child_id, $parent_id, blessed($child), $child->value,
            );

            $self->{_mapping}{$child_id} = $child;
            push @parents, $child_id;
        }
    }

    $sth->finish;

    return $self;
}

#*_commit = \&_create;

use Data::Dumper;
sub _commit {
    my $self = shift;

    my $dbh = $self->{_dbh};
    my %sql = $self->_build_sql;

    foreach my $change ( @{$self->{_changes}} ) {
        if ( $change->{action} eq 'change_value' ) {
            my $sth = $dbh->prepare_cached( $sql{set_value} );
            $sth->execute(
                $change->{new_value},
                $change->{node}->meta->{refaddr $self}{id},
            );
            $sth->finish;
        }
        elsif ( $change->{action} eq 'add_child' ) {
            foreach my $child ( @{$change->{children}} ) {
                $self->_create( $child );
            }
        }
        elsif ( $change->{action} eq 'remove_child' ) {
            foreach my $child ( @{$change->{children}} ) {
                my $sth = $dbh->prepare_cached( $sql{set_parent} );
                $sth->execute(
                    undef,
                    $child->meta->{refaddr $self}{id},
                );
                $sth->finish;
            }
        }
    }

    return $self;
}

sub _build_sql {
    my $self = shift;

    my %sql = (
        fetch => <<"__END_SQL__",
SELECT $self->{_id_col}        AS id
      ,$self->{_parent_id_col} AS parent_id
      ,$self->{_class_col}     AS class
      ,$self->{_value_col}     AS value
  FROM $self->{_table} AS tree
 WHERE tree.$self->{_id_col} = ?
__END_SQL__
        fetch_children => <<"__END_SQL__",
SELECT $self->{_id_col}        AS id
      ,$self->{_class_col}     AS class
      ,$self->{_value_col}     AS value
  FROM $self->{_table} AS tree
 WHERE tree.$self->{_parent_id_col} = ?
__END_SQL__
        next_id => <<"__END_SQL__",
SELECT MAX($self->{_id_col}) + 1
  FROM $self->{_table}
__END_SQL__
        create_node => <<"__END_SQL__",
REPLACE INTO $self->{_table} (
    $self->{_id_col}
   ,$self->{_parent_id_col}
   ,$self->{_class_col}
   ,$self->{_value_col}
) VALUES ( ?, ?, ?, ? )
__END_SQL__
        set_value => <<"__END_SQL__",
UPDATE $self->{_table}
   SET $self->{_value_col} = ?
 WHERE $self->{_id_col} = ?
__END_SQL__
        set_parent => <<"__END_SQL__",
UPDATE $self->{_table}
   SET $self->{_parent_id_col} = ?
 WHERE $self->{_id_col} = ?
__END_SQL__
    );

    return %sql;
}

1;
__END__

requires "Module::Setup::Flavor";
requires "Module::Setup::Flavor::SelectVC";

on test => sub {
    requires 'Test::More';
};

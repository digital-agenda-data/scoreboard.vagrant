ld_dir_all('/tmp/prod_export_graph','*.ttl','http://unknown.org');

rdf_loader_run();

checkpoint;

select count(1) from rdf_quad;

exit;

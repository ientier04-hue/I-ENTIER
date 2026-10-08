-- Unknown coordinates/delivery remain NULL until verified by the pharmacy.
alter table ientier.pharmacies
  add column latitude double precision,
  add column longitude double precision,
  add column delivery_available boolean,
  add constraint pharmacies_latitude_range check (latitude between -90 and 90),
  add constraint pharmacies_longitude_range check (longitude between -180 and 180),
  add constraint pharmacies_coordinates_pair check ((latitude is null) = (longitude is null));

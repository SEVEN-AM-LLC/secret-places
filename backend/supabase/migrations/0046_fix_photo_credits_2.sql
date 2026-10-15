-- Same clean-up as 0043 for the variant without "~commonswiki".
update public.places set photo_credit = regexp_replace(photo_credit,
  'Photo: No machine-readable author provided\. (.+?)(~commonswiki)? assumed[^·]*·', 'Photo: \1 ·')
  where photo_credit like 'Photo: No machine-readable author provided.%';
update public.places set photo_credit = replace(photo_credit, 'Photo: AnonymousUnknown author ·', 'Photo: Unknown author ·')
  where photo_credit like 'Photo: AnonymousUnknown author ·%';

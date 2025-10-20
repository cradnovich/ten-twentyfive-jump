defmodule AdvisorAgent.Repo.Migrations.AddUniqueIndexesToDocuments do
  use Ecto.Migration

  def up do
    # Remove duplicate documents before adding unique indexes
    # Keep only the oldest record (lowest id) for each duplicate

    # Remove duplicate Gmail emails
    execute """
    DELETE FROM documents a USING documents b
    WHERE a.id > b.id
    AND a.metadata->>'source' = 'gmail'
    AND b.metadata->>'source' = 'gmail'
    AND a.metadata->>'message_id' = b.metadata->>'message_id'
    """

    # Remove duplicate Hubspot contacts
    execute """
    DELETE FROM documents a USING documents b
    WHERE a.id > b.id
    AND a.metadata->>'source' = 'hubspot_contact'
    AND b.metadata->>'source' = 'hubspot_contact'
    AND a.metadata->>'contact_id' = b.metadata->>'contact_id'
    """

    # Remove duplicate Hubspot notes
    execute """
    DELETE FROM documents a USING documents b
    WHERE a.id > b.id
    AND a.metadata->>'source' = 'hubspot_note'
    AND b.metadata->>'source' = 'hubspot_note'
    AND a.metadata->>'note_id' = b.metadata->>'note_id'
    """

    # Create unique partial indexes for each source type to prevent duplicates
    # Uses JSONB operators to extract metadata fields

    # Unique index for Gmail emails - prevents duplicate message_id from same source
    create unique_index(:documents, ["(metadata->>'source')", "(metadata->>'message_id')"],
      name: :documents_gmail_message_unique_index,
      where: "metadata->>'source' = 'gmail'"
    )

    # Unique index for Hubspot contacts - prevents duplicate contact_id from same source
    create unique_index(:documents, ["(metadata->>'source')", "(metadata->>'contact_id')"],
      name: :documents_hubspot_contact_unique_index,
      where: "metadata->>'source' = 'hubspot_contact'"
    )

    # Unique index for Hubspot notes - prevents duplicate note_id from same source
    create unique_index(:documents, ["(metadata->>'source')", "(metadata->>'note_id')"],
      name: :documents_hubspot_note_unique_index,
      where: "metadata->>'source' = 'hubspot_note'"
    )
  end

  def down do
    # Drop the unique indexes
    drop index(:documents, ["(metadata->>'source')", "(metadata->>'message_id')"],
      name: :documents_gmail_message_unique_index
    )

    drop index(:documents, ["(metadata->>'source')", "(metadata->>'contact_id')"],
      name: :documents_hubspot_contact_unique_index
    )

    drop index(:documents, ["(metadata->>'source')", "(metadata->>'note_id')"],
      name: :documents_hubspot_note_unique_index
    )
  end
end

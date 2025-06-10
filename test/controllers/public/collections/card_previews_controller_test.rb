require "test_helper"

class Public::Collections::CardPreviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin

    collections(:writebook).publish
  end

  test "render considering cards" do
    assert cards(:text).considering?
    assert_not cards(:logo).considering?

    get public_collection_card_previews_path(collections(:writebook).publication.key, target: "considering-cards", format: :turbo_stream)

    assert_select ".card", text: /#{cards(:text).title}/
    assert_select ".card", text: cards(:logo).title, count: 0
  end

  test "render doing cards" do
    assert cards(:logo).doing?
    assert_not cards(:text).doing?

    get public_collection_card_previews_path(collections(:writebook).publication.key, target: "doing-cards", format: :turbo_stream)

    assert_select ".card", text: /#{cards(:logo).title}/
    assert_select ".card", text: cards(:text).title, count: 0
  end

  test "render closed cards" do
    assert cards(:shipping).closed?
    assert_not cards(:text).doing?

    get public_collection_card_previews_path(collections(:writebook).publication.key, target: "closed-cards", format: :turbo_stream)

    assert_select ".card", text: /#{cards(:shipping).title}/
    assert_select ".card", text: cards(:text).title, count: 0
  end

  test "bad response for unknown target" do
    get public_collection_card_previews_path(collections(:writebook).publication.key, format: :turbo_stream)
    assert_response :bad_request
  end
end

require "test_helper"

class Public::CollectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin

    collections(:writebook).publish
  end

  test "show" do
    get published_collection_path(collections(:writebook))
    assert_response :success
  end

  test "not found if the collection is not published" do
    key = collections(:writebook).publication.key

    collections(:writebook).unpublish
    get public_collection_path(key)

    assert_response :not_found
  end
end

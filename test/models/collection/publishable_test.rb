require "test_helper"

class Collection::PublishableTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
  end

  test "published scope" do
    collections(:writebook).publish
    assert_includes Collection.published, collections(:writebook)
    assert_not_includes Collection.published, collections(:private)
  end

  test "published?" do
    assert_not collections(:writebook).published?
    collections(:writebook).publish
    assert collections(:writebook).published?
  end

  test "publish and unpublish" do
    assert_not collections(:writebook).published?

    assert_difference -> { Collection::Publication.count }, +1 do
      collections(:writebook).publish
    end

    assert collections(:writebook).published?

    assert_difference -> { Collection::Publication.count }, -1 do
      collections(:writebook).unpublish
    end

    assert_not collections(:writebook).reload.published?
  end

  test "find collection by publication key" do
    collections(:writebook).publish
    assert_equal collections(:writebook), Collection.find_by_published_key(collections(:writebook).publication.key)

    assert_raise ActiveRecord::RecordNotFound do
      Collection.find_by_published_key("invalid")
    end
  end

  test "publish doesn't create duplicate publications" do
    collections(:writebook).publish
    original_publication = collections(:writebook).publication

    assert_no_difference -> { Collection::Publication.count } do
      collections(:writebook).publish
    end

    assert_equal original_publication, collections(:writebook).reload.publication
  end
end

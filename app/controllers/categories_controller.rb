class CategoriesController < ApplicationController
  before_action :require_admin, except: %i[index show]
  before_action :set_category, only: %i[show edit update destroy]

  def index
    @categories = catalog_categories
    @document_counts = current_user.documents.group(:category_id).count
  end

  def show
    @documents = current_user.documents.where(category: @category).recent.limit(100)
  end

  def new
    @category = Category.new(auto_create: true, color: "#5c5a52")
  end

  def create
    @category = Category.new(category_params)
    if @category.save
      FileUtils.mkdir_p(SafeStoragePath.resolve(current_user.sorted_root, @category.directory_path))
      redirect_to categories_path, notice: "Category created and directory prepared."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @category.update(category_params)
      FileUtils.mkdir_p(SafeStoragePath.resolve(current_user.sorted_root, @category.directory_path))
      redirect_to @category, notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @category.documents.exists?
      redirect_to categories_path, alert: "Move or delete documents first (including other users’ files)."
    else
      @category.destroy
      redirect_to categories_path, notice: "Category deleted."
    end
  end

  private

  def set_category
    @category = catalog_categories.find(params[:id])
  end

  def catalog_categories
    current_user.assignable_categories
  end

  def category_params
    params.require(:category).permit(
      :name, :slug, :description, :directory_path, :keywords,
      :auto_create, :position, :color
    )
  end
end

class CategoriesController < ApplicationController
  before_action :set_category, only: %i[show edit update destroy]

  def index
    @categories = Category.ordered.includes(:documents)
  end

  def show
    @documents = @category.documents.recent.limit(100)
  end

  def new
    @category = Category.new(auto_create: true, color: "#6366f1")
  end

  def create
    @category = Category.new(category_params)
    if @category.save
      @category.ensure_directory!
      redirect_to categories_path, notice: "Category created and directory prepared."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @category.update(category_params)
      @category.ensure_directory!
      redirect_to @category, notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @category.documents.exists?
      redirect_to categories_path, alert: "Move or delete documents first."
    else
      @category.destroy
      redirect_to categories_path, notice: "Category deleted."
    end
  end

  private

  def set_category
    @category = Category.find(params[:id])
  end

  def category_params
    params.require(:category).permit(
      :name, :slug, :description, :directory_path, :keywords,
      :auto_create, :position, :color
    )
  end
end

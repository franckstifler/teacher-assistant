# defmodule TeacherAssistant.Resources.TermTest do
#   use TeacherAssistant.DataCase

#   alias TeacherAssistant.Academics.Term

#   require Ash.Query

#   setup %{tenant: tenant} do
#     user = generate(admin_user(tenant: tenant))
#     %{user: user}
#   end

#   describe "TeacherAssistant.Academics.read_terms" do
#     test "list terms", %{tenant: tenant, user: user} do
#       term = generate(term(actor: user, tenant: tenant))

#       assert [result] = TeacherAssistant.Academics.read_terms!(tenant: tenant, actor: user)

#       assert result.id == term.id
#       assert result.name == term.name
#       assert result.description == term.description
#     end
#   end

#   describe "TeacherAssistant.Academics.create_term" do
#     test "with valid data creates a term", %{tenant: tenant, user: user} do
#       check all(input <- Ash.Generator.action_input(Term, :create)) do
#         term =
#           TeacherAssistant.Academics.create_term!(input,
#             tenant: tenant,
#             actor: user,
#             authorize?: false
#           )

#         assert term.name == input[:name]
#         assert term.description == value_or_nil(input, :description)
#       end
#     end

#     test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
#       assert {:error, %Ash.Error.Invalid{errors: errors}} =
#                TeacherAssistant.Academics.create_term(%{name: nil, description: nil},
#                  tenant: tenant,
#                  actor: user,
#                  authorize?: false
#                )

#       assert_field_error(errors, :name, error_class: Ash.Error.Changes.Required)
#     end
#   end

#   describe "TeacherAssistant.Academics.update_term" do
#     test "updates a term", %{tenant: tenant, user: user} do
#       check all(input <- Ash.Generator.action_input(Term, :update)) do
#         term = generate(term(tenant: tenant, actor: user))

#         updated_term =
#           TeacherAssistant.Academics.update_term!(term, input,
#             tenant: tenant,
#             actor: user,
#             authorize?: false
#           )

#         assert updated_term.name == input[:name]
#         assert updated_term.description == value_or_nil(input, :description, term.description)
#       end
#     end

#     test "with invalid data returns error changeset", %{tenant: tenant, user: user} do
#       term = generate(term(tenant: tenant, actor: user))

#       assert {:error, %Ash.Error.Invalid{errors: errors}} =
#                TeacherAssistant.Academics.update_term(term, %{name: nil, description: nil},
#                  tenant: tenant,
#                  actor: user,
#                  authorize?: false
#                )

#       assert_field_error(errors, :name, error_class: Ash.Error.Changes.Required)
#     end
#   end

#   describe "TeacherAssistant.Academics.destroy_term" do
#     test "destroys a term", %{tenant: tenant, user: user} do
#       term = generate(term(tenant: tenant, actor: user))

#       TeacherAssistant.Academics.destroy_term!(term,
#         tenant: tenant,
#         actor: user,
#         authorize?: false
#       )

#       assert Ash.count!(Term, tenant: tenant, actor: user, authorize?: false) == 0
#     end
#   end

#   describe "policies test" do
#     test "read terms", %{tenant: tenant} do
#       admin = generate(admin_user(tenant: tenant))
#       user = generate(user(tenant: tenant))
#       term = generate(term(tenant: tenant))

#       assert TeacherAssistant.Academics.can_read_terms?(admin, tenant: tenant, data: term)
#       assert TeacherAssistant.Academics.can_read_terms?(user, tenant: tenant, data: term)
#     end

#     test "create term", %{tenant: tenant} do
#       admin = generate(admin_user(tenant: tenant))
#       user = generate(user(tenant: tenant))

#       assert TeacherAssistant.Academics.can_create_term?(admin, tenant: tenant)
#       assert TeacherAssistant.Academics.can_create_term?(user, tenant: tenant)
#     end

#     test "update term", %{tenant: tenant} do
#       admin = generate(admin_user(tenant: tenant))
#       user = generate(user(tenant: tenant))
#       term = generate(term(tenant: tenant, actor: admin))

#       assert TeacherAssistant.Academics.can_update_term?(admin, term, tenant: tenant)
#       assert TeacherAssistant.Academics.can_update_term?(user, term, tenant: tenant)
#     end

#     test "destroy term", %{tenant: tenant} do
#       admin = generate(admin_user(tenant: tenant))
#       user = generate(user(tenant: tenant))
#       term = generate(term(tenant: tenant, actor: admin))

#       assert TeacherAssistant.Academics.can_destroy_term?(admin, term, tenant: tenant)
#       assert TeacherAssistant.Academics.can_destroy_term?(user, term, tenant: tenant)
#     end
#   end
# end
